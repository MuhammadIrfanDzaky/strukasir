<?php

namespace App\Services;

use App\Enums\Feature;
use App\Http\Resources\OrderResource;
use App\Models\Customer;
use App\Models\Order;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Pesan WhatsApp lewat tautan wa.me (gratis, dikirim manual dari WhatsApp di tablet/HP).
 * Teks disusun server dari template + data pelanggan; tablet hanya menerima tautan siap buka.
 */
class MessagingService
{
    /** Template: kunci → [judul, teks bawaan]. */
    public const TEMPLATES = [
        'receipt' => ['Struk digital', "Halo {nama}, terima kasih sudah belanja di {kedai}!\n\n{struk}\n\nSampai jumpa lagi 🙏"],
        'birthday' => ['Ucapan ulang tahun', 'Selamat ulang tahun, {nama}! 🎉 Semoga sehat & bahagia selalu. Mampir ke {kedai} ya, kami tunggu.'],
        'winback' => ['Sapa pelanggan lama', 'Halo {nama}, sudah lama tidak mampir ke {kedai}. Kami kangen! Ditunggu kedatangannya ya 😊'],
        'credit_reminder' => ['Pengingat kasbon', 'Halo {nama}, sekadar mengingatkan kasbon di {kedai} saat ini {sisa_kasbon}. Terima kasih 🙏'],
        'greeting' => ['Sapaan umum', 'Halo {nama}, salam dari {kedai}!'],
    ];

    /** Isian yang bisa dipakai di template (ditampilkan di layar owner). */
    public const PLACEHOLDERS = ['{nama}', '{kedai}', '{kode}', '{tingkat}', '{stempel}', '{sisa_kasbon}', '{struk}', '{total}', '{nomor}'];

    public const AUDIENCES = ['birthday', 'winback', 'credit_reminder'];

    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::CustomerMessaging);
    }

    /** @return array<string, string> teks template kedai (bawaan bila belum diubah) */
    public function templates(): array
    {
        $custom = DB::table('message_templates')->pluck('body', 'key')->all();

        return collect(self::TEMPLATES)->mapWithKeys(fn ($t, $key) => [$key => $custom[$key] ?? $t[1]])->all();
    }

    /** @param  array<string, ?string>  $bodies  null / kosong = kembali ke teks bawaan */
    public function saveTemplates(array $bodies): void
    {
        $tenantId = app(TenantContext::class)->id();
        foreach ($bodies as $key => $body) {
            $body = trim((string) $body);
            if ($body === '' || $body === self::TEMPLATES[$key][1]) {
                DB::table('message_templates')->where('key', $key)->delete();

                continue;
            }
            DB::table('message_templates')->upsert(
                [['tenant_id' => $tenantId, 'key' => $key, 'body' => $body, 'created_at' => now(), 'updated_at' => now()]],
                ['tenant_id', 'key'],
                ['body', 'updated_at'],
            );
        }
    }

    /**
     * Susun pesan untuk satu pelanggan & catat di riwayat.
     *
     * @return array{url: string, text: string}
     */
    public function prepare(Customer $customer, string $template, ?Order $order, User $user): array
    {
        if ($customer->phone === null) {
            throw ValidationException::withMessages(['customer' => 'Pelanggan ini belum punya no HP.']);
        }
        if ($template === 'receipt' && ($order === null || $order->customer_id !== $customer->id || $order->status !== 'paid')) {
            throw ValidationException::withMessages(['order_id' => 'Struk hanya untuk order lunas milik pelanggan ini.']);
        }

        $text = $this->render($this->templates()[$template], $customer, $order);
        DB::table('message_logs')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $customer->tenant_id,
            'customer_id' => $customer->id,
            'template' => $template,
            'order_id' => $order?->id,
            'sent_by' => $user->id,
            'created_at' => now(),
        ]);

        return ['url' => 'https://wa.me/'.ltrim($customer->phone, '+').'?text='.rawurlencode($text), 'text' => $text];
    }

    public function render(string $body, Customer $customer, ?Order $order): string
    {
        $shop = TenantSetting::query()->value('receipt_name') ?: Tenant::query()->whereKey($customer->tenant_id)->value('name');
        $loyalty = app(LoyaltyService::class);
        $program = $loyalty->activeProgram();
        $tiers = app(TierService::class);
        $tier = $tiers->enabled() ? $tiers->evaluate($customer)['tier'] : null;
        $credit = app(CreditService::class);

        $values = [
            '{nama}' => $customer->name,
            '{kedai}' => $shop,
            '{kode}' => $customer->code,
            '{tingkat}' => $tier?->name ?? '',
            '{stempel}' => $program ? $loyalty->balance($customer->id, $program)['balance'].' '.$program->unit() : '',
            '{sisa_kasbon}' => $credit->enabled() ? self::rp($credit->balance($customer->id)) : '',
            '{struk}' => $order ? $this->receiptText($order) : '',
            '{total}' => $order ? self::rp($order->grand_total) : '',
            '{nomor}' => $order?->number ?? '',
        ];

        return trim(strtr($body, $values));
    }

    /** Struk ringkas untuk WhatsApp (teks biasa, *tebal* gaya WhatsApp). */
    public function receiptText(Order $order): string
    {
        $o = (new OrderResource($order))->resolve();
        $lines = ['*Struk '.$o['number'].'*', Carbon::parse($o['paid_at'] ?? $o['created_at'])->setTimezone($this->timezone())->format('d/m/Y H:i')];
        foreach ($o['items'] as $i) {
            $mods = collect($i['modifiers'])->map(fn ($m) => $m['qty'] > 1 ? "{$m['name']} x{$m['qty']}" : $m['name'])->implode(', ');
            $lines[] = "{$i['qty']}x {$i['name']}".($mods ? " ({$mods})" : '').' — '.self::rp($i['line_total']);
        }
        if ($o['discount_total'] > 0) {
            $lines[] = 'Potongan: -'.self::rp($o['discount_total']);
        }
        foreach ([['service_total', 'Service'], ['tax_total', 'Pajak']] as [$key, $label]) {
            if ($o[$key] > 0) {
                $lines[] = "{$label}: ".self::rp($o[$key]);
            }
        }
        $lines[] = '*Total: '.self::rp($o['grand_total']).'*';
        if ($o['loyalty']) {
            $l = $o['loyalty'];
            $lines[] = "{$l['program']}: +{$l['earned']} {$l['unit']}, saldo {$l['balance']} {$l['unit']}";
        }
        if ($o['credit']) {
            $lines[] = 'Sisa kasbon: '.self::rp($o['credit']['balance']);
        }

        return implode("\n", $lines);
    }

    /**
     * Daftar siap-kirim untuk owner (hanya yang punya no HP), dengan waktu terakhir dikirim template itu.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public function audience(string $template): Collection
    {
        $query = app(CustomerService::class)->withStats()->whereNotNull('customers.phone');
        $tz = $this->timezone();
        $today = Carbon::now($tz);

        match ($template) {
            'birthday' => $query->whereNotNull('customers.birth_date'),
            'winback' => app(CustomerService::class)->search($query, null, 'lost', 'recent'),
            default => $query->where('cb.credit_balance', '>', 0)->orderByRaw('cb.credit_balance desc'),
        };

        $customers = $template === 'birthday'
            // Ulang tahun 7 hari ke depan (termasuk hari ini); 29 Feb dirayakan 28 Feb di tahun biasa.
            ? $query->get()
                ->map(fn (Customer $c) => [$c, self::daysUntilBirthday($c->birth_date, $today)])
                ->filter(fn ($x) => $x[1] <= 6)
                ->sortBy(fn ($x) => $x[1])
                ->map(fn ($x) => $x[0])
                ->values()
            : $query->limit(200)->get();
        $last = DB::table('message_logs')->where('template', $template)->whereIn('customer_id', $customers->pluck('id'))
            ->groupBy('customer_id')->selectRaw('customer_id, max(created_at) as at')->pluck('at', 'customer_id');

        return $customers->map(fn (Customer $c) => [
            'id' => $c->id,
            'code' => $c->code,
            'name' => $c->name,
            'birth_date' => $c->birth_date?->toDateString(),
            'last_visit_at' => $c->last_visit_at ? Carbon::parse($c->last_visit_at, 'UTC')->toIso8601String() : null,
            'credit_balance' => (int) $c->credit_balance,
            'last_sent_at' => isset($last[$c->id]) ? Carbon::parse($last[$c->id], 'UTC')->toIso8601String() : null,
        ])->values();
    }

    /** Hari menuju ulang tahun berikutnya (0 = hari ini). */
    public static function daysUntilBirthday(Carbon $birth, Carbon $today): int
    {
        $day = $today->copy()->startOfDay();
        foreach ([$day->year, $day->year + 1] as $year) {
            $date = Carbon::create($year, $birth->month, min($birth->day, Carbon::create($year, $birth->month, 1)->daysInMonth), 0, 0, 0, $day->timezone);
            if ($date->gte($day)) {
                return (int) $day->diffInDays($date);
            }
        }

        return 366;
    }

    private function timezone(): string
    {
        return Tenant::query()->whereKey(app(TenantContext::class)->id())->value('timezone') ?: 'Asia/Jakarta';
    }

    private static function rp(int $amount): string
    {
        return 'Rp'.number_format($amount, 0, ',', '.');
    }
}
