<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\Order;
use App\Models\TenantSetting;
use App\Support\Audit;
use App\Support\PhoneNumber;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Pelanggan / member: kode berurutan, statistik belanja, kelompok, anonimisasi (UU PDP), import CSV.
 *
 * Statistik dihitung dari order `paid` saja (order void tidak menambah kunjungan/belanja).
 * Audit log hanya mencatat kode & nama kolom yang berubah, bukan isi data pribadinya.
 */
class CustomerService
{
    /** Batas hari untuk kelompok "baru" & "menghilang". */
    public const RECENT_DAYS = 30;

    /** Minimal kunjungan untuk kelompok "setia". */
    public const LOYAL_VISITS = 5;

    public const SEGMENTS = ['new', 'loyal', 'lost'];

    public const MAX_IMPORT_ROWS = 2000;

    private const IMPORT_ALIASES = [
        'name' => ['nama', 'nama pelanggan', 'namapelanggan', 'pelanggan', 'name', 'customer', 'customer name', 'nama member'],
        'phone' => ['hp', 'no hp', 'nohp', 'no. hp', 'nomor hp', 'no telp', 'no. telp', 'telepon', 'telp', 'phone', 'no whatsapp', 'whatsapp', 'wa', 'nomor telepon', 'handphone'],
        'birth_date' => ['tanggal lahir', 'tgl lahir', 'tgl. lahir', 'ulang tahun', 'birthday', 'birth date', 'date of birth'],
        'note' => ['catatan', 'keterangan', 'note', 'notes'],
    ];

    public function phoneRequired(): bool
    {
        return (bool) TenantSetting::query()->value('customer_phone_required');
    }

    /** @param  array{name: string, phone?: ?string, birth_date?: ?string, note?: ?string}  $data */
    public function create(array $data): Customer
    {
        $customer = $this->guardPhone(fn () => DB::transaction(function () use ($data) {
            $customer = new Customer($this->clean($data));
            $customer->code = $this->nextCode();
            $customer->save();

            return $customer;
        }));

        Audit::record('customer.created', $customer, after: ['code' => $customer->code]);

        return $customer;
    }

    /** @param  array<string, mixed>  $data */
    public function update(Customer $customer, array $data): Customer
    {
        $customer->fill($this->clean($data));
        $changed = array_keys($customer->getDirty());
        if ($changed === []) {
            return $customer;
        }
        $this->guardPhone(fn () => $customer->save());
        Audit::record('customer.updated', $customer, after: ['code' => $customer->code, 'fields' => $changed]);

        return $customer;
    }

    /**
     * Hapus data pribadi atas permintaan pelanggan. Baris tetap ada (statistik & riwayat order tetap
     * utuh untuk laporan), tetapi nama/HP/tanggal lahir/catatan dikosongkan dan label nama di order-
     * ordernya ikut dihapus. Tidak bisa dibatalkan.
     */
    public function anonymize(Customer $customer): void
    {
        if ($customer->isAnonymized()) {
            return;
        }
        DB::transaction(function () use ($customer) {
            $name = $customer->name;
            Order::query()->where('customer_id', $customer->id)
                ->whereRaw('lower(customer_label) = lower(?)', [$name])
                ->update(['customer_label' => null]);

            $customer->forceFill([
                'name' => 'Pelanggan dihapus',
                'phone' => null,
                'birth_date' => null,
                'note' => null,
                'anonymized_at' => now(),
            ])->save();
        });

        Audit::record('customer.anonymized', $customer, after: ['code' => $customer->code]);
    }

    /**
     * Pelanggan aktif + statistik belanja (visits, total_spent, last_visit_at, first_visit_at).
     *
     * @return Builder<Customer>
     */
    public function withStats(): Builder
    {
        $stats = Order::query()
            ->where('status', 'paid')
            ->whereNotNull('customer_id')
            ->groupBy('customer_id')
            ->selectRaw('customer_id, count(*) as visits, sum(grand_total) as total_spent, max(paid_at) as last_visit_at, min(paid_at) as first_visit_at');

        return Customer::query()
            ->active()
            ->leftJoinSub($stats, 's', 's.customer_id', '=', 'customers.id')
            ->select('customers.*')
            ->selectRaw('coalesce(s.visits, 0) as visits, coalesce(s.total_spent, 0) as total_spent, s.last_visit_at, s.first_visit_at');
    }

    /**
     * @param  Builder<Customer>  $query  hasil withStats()
     * @return Builder<Customer>
     */
    public function search(Builder $query, ?string $q, ?string $segment, string $sort): Builder
    {
        $q = trim((string) $q);
        if ($q !== '') {
            $digits = PhoneNumber::searchDigits($q);
            $query->where(function (Builder $w) use ($q, $digits) {
                $like = '%'.addcslashes(mb_strtolower($q), '%_\\').'%';
                $w->whereRaw('lower(customers.name) like ?', [$like])
                    ->orWhereRaw('lower(customers.code) like ?', [$like]);
                if ($digits !== null) {
                    $w->orWhere('customers.phone', 'like', '%'.$digits.'%');
                }
            });
        }

        $since = Carbon::now()->subDays(self::RECENT_DAYS);
        match ($segment) {
            // Baru: pertama terdaftar dalam 30 hari terakhir.
            'new' => $query->where('customers.created_at', '>=', $since),
            // Setia: sering datang dan masih aktif belakangan ini.
            'loyal' => $query->where('s.visits', '>=', self::LOYAL_VISITS)->where('s.last_visit_at', '>=', $since),
            // Menghilang: pernah belanja, tapi tidak datang 30 hari terakhir.
            'lost' => $query->where('s.last_visit_at', '<', $since),
            default => null,
        };

        return match ($sort) {
            'recent' => $query->orderByRaw('s.last_visit_at desc nulls last')->orderBy('customers.name'),
            'top' => $query->orderByRaw('coalesce(s.total_spent, 0) desc')->orderBy('customers.name'),
            'newest' => $query->orderByDesc('customers.created_at'),
            default => $query->orderByRaw('lower(customers.name)')->orderBy('customers.code'),
        };
    }

    /** @return array{new: int, loyal: int, lost: int, all: int} */
    public function segmentCounts(): array
    {
        $counts = ['all' => $this->withStats()->count()];
        foreach (self::SEGMENTS as $segment) {
            $counts[$segment] = $this->search($this->withStats(), null, $segment, 'name')->reorder()->count();
        }

        return $counts;
    }

    /**
     * Detail untuk owner: produk favorit & order terakhir.
     *
     * @return array{favorites: list<array{name: string, qty: int}>, recent_orders: list<array<string, mixed>>}
     */
    public function history(Customer $customer): array
    {
        $favorites = DB::table('order_items')
            ->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->where('orders.customer_id', $customer->id)
            ->where('orders.status', 'paid')
            ->groupBy('order_items.name')
            ->orderByRaw('sum(order_items.qty) desc')
            ->orderBy('order_items.name')
            ->limit(5)
            ->selectRaw('order_items.name, sum(order_items.qty) as qty')
            ->get()
            ->map(fn ($r) => ['name' => $r->name, 'qty' => (int) $r->qty])
            ->all();

        $recent = Order::query()
            ->where('customer_id', $customer->id)
            ->whereIn('status', ['paid', 'void'])
            ->orderByDesc('created_at')
            ->limit(10)
            ->get(['id', 'number', 'status', 'grand_total', 'business_date', 'paid_at', 'created_at'])
            ->map(fn (Order $o) => [
                'id' => $o->id,
                'number' => $o->number,
                'status' => $o->status,
                'grand_total' => $o->grand_total,
                'business_date' => $o->business_date->toDateString(),
                'paid_at' => $o->paid_at?->toIso8601String(),
            ])
            ->all();

        return ['favorites' => $favorites, 'recent_orders' => $recent];
    }

    /**
     * Import pelanggan dari CSV. Semua-atau-tidak-sama-sekali, sama seperti import produk.
     * Dicocokkan lewat no HP (bila ada), lalu lewat nama bila namanya unik dan tanpa HP; sisanya baru.
     *
     * @return array{created: int, updated: int, errors: list<array{row: int, message: string}>, saved: bool}
     */
    public function import(string $csv, bool $dryRun): array
    {
        $result = ['created' => 0, 'updated' => 0, 'errors' => [], 'saved' => false];
        $rows = $this->parseCsv($csv, $result['errors']);
        if ($result['errors'] !== []) {
            return $result;
        }

        $phoneRequired = $this->phoneRequired();
        $existing = Customer::query()->active()->get();
        $byPhone = $existing->whereNotNull('phone')->keyBy('phone');
        $byName = $existing->groupBy(fn (Customer $c) => mb_strtolower($c->name));
        $plan = [];
        $seenPhones = [];
        $seenCustomers = [];

        foreach ($rows as $row) {
            $line = (int) $row['_row'];
            $fail = function (string $message) use (&$result, $line) {
                $result['errors'][] = ['row' => $line, 'message' => $message];
            };

            $name = mb_substr(trim(preg_replace('/\s+/', ' ', $row['name'] ?? '')), 0, 80);
            if ($name === '') {
                $fail('Nama pelanggan kosong.');

                continue;
            }
            $fields = ['name' => $name];

            $rawPhone = $row['phone'] ?? '';
            $phone = null;
            if ($rawPhone !== '') {
                $phone = PhoneNumber::normalize($rawPhone);
                if ($phone === null) {
                    $fail("No HP \"{$rawPhone}\" tidak valid.");

                    continue;
                }
                if (isset($seenPhones[$phone])) {
                    $fail("No HP \"{$rawPhone}\" dobel (juga di baris {$seenPhones[$phone]}).");

                    continue;
                }
                $seenPhones[$phone] = $line;
                $fields['phone'] = $phone;
            }

            if (($row['birth_date'] ?? '') !== '') {
                $birth = $this->date($row['birth_date']);
                if ($birth === null) {
                    $fail("Tanggal lahir \"{$row['birth_date']}\" tidak dikenali (pakai 31/12/1990 atau 1990-12-31).");

                    continue;
                }
                $fields['birth_date'] = $birth;
            }
            if (($row['note'] ?? '') !== '') {
                $fields['note'] = mb_substr($row['note'], 0, 200);
            }

            $customer = $phone !== null ? ($byPhone[$phone] ?? null) : null;
            if ($customer === null && $phone === null) {
                $same = $byName[mb_strtolower($name)] ?? collect();
                $customer = $same->count() === 1 ? $same->first() : null;
            }
            if ($customer === null && $phone === null && $phoneRequired) {
                $fail('No HP wajib diisi (Pengaturan → Fitur → No HP pelanggan wajib).');

                continue;
            }
            if ($customer !== null) {
                if (isset($seenCustomers[$customer->id])) {
                    $fail("Pelanggan \"{$name}\" muncul dua kali (juga di baris {$seenCustomers[$customer->id]}).");

                    continue;
                }
                $seenCustomers[$customer->id] = $line;
            }

            $plan[] = ['customer' => $customer, 'fields' => $fields];
        }

        if ($result['errors'] !== []) {
            return $result;
        }
        $result['created'] = count(array_filter($plan, fn ($p) => $p['customer'] === null));
        $result['updated'] = count($plan) - $result['created'];
        if ($dryRun) {
            return $result;
        }

        DB::transaction(function () use ($plan) {
            foreach ($plan as $p) {
                $customer = $p['customer'] ?? new Customer;
                $customer->fill($p['fields']);
                if (! $customer->exists) {
                    $customer->code = $this->nextCode();
                }
                $customer->save();
            }
        });
        Audit::record('customer.imported', null, after: ['created' => $result['created'], 'updated' => $result['updated']]);
        $result['saved'] = true;

        return $result;
    }

    /** Kode member berikutnya (M0001, …). Penghitung dinaikkan atomik di baris setting kedai. */
    private function nextCode(): string
    {
        $seq = DB::selectOne(
            'UPDATE tenant_settings SET customer_seq = customer_seq + 1 WHERE tenant_id = ? RETURNING customer_seq',
            // Konteks diambil saat dipakai: service ini bisa dipegang controller yang hidup lama.
            [app(TenantContext::class)->id()],
        )->customer_seq;

        return 'M'.str_pad((string) $seq, 4, '0', STR_PAD_LEFT);
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function clean(array $data): array
    {
        $out = [];
        if (array_key_exists('name', $data)) {
            $out['name'] = trim(preg_replace('/\s+/', ' ', (string) $data['name']));
        }
        if (array_key_exists('phone', $data)) {
            $out['phone'] = PhoneNumber::normalize($data['phone']);
        }
        foreach (['birth_date', 'note'] as $key) {
            if (array_key_exists($key, $data)) {
                $value = is_string($data[$key]) ? trim($data[$key]) : $data[$key];
                $out[$key] = $value === '' ? null : $value;
            }
        }

        return $out;
    }

    /**
     * @template T
     *
     * @param  callable(): T  $save
     * @return T
     */
    private function guardPhone(callable $save): mixed
    {
        try {
            return $save();
        } catch (UniqueConstraintViolationException) {
            // Dua tablet mendaftarkan nomor yang sama bersamaan: yang kedua ditolak database.
            throw ValidationException::withMessages(['phone' => 'No HP ini sudah terdaftar untuk pelanggan lain.']);
        }
    }

    /** @return list<array<string, string>> */
    private function parseCsv(string $csv, array &$errors): array
    {
        $csv = preg_replace('/^\xEF\xBB\xBF/', '', str_replace(["\r\n", "\r"], "\n", $csv));
        $lines = array_values(array_filter(explode("\n", $csv), fn ($l) => trim($l) !== ''));
        if (count($lines) < 2) {
            $errors[] = ['row' => 1, 'message' => 'File kosong atau hanya berisi judul kolom.'];

            return [];
        }
        if (count($lines) - 1 > self::MAX_IMPORT_ROWS) {
            $errors[] = ['row' => 1, 'message' => 'Maksimal '.self::MAX_IMPORT_ROWS.' pelanggan per import.'];

            return [];
        }

        $delimiter = substr_count($lines[0], ';') > substr_count($lines[0], ',') ? ';' : ',';
        $columns = [];
        foreach (str_getcsv($lines[0], $delimiter, '"', '') as $i => $header) {
            $h = trim(mb_strtolower(trim(preg_replace('/\s+/', ' ', $header))), " *\t");
            foreach (self::IMPORT_ALIASES as $key => $names) {
                if (in_array($h, $names, true) && ! in_array($key, $columns, true)) {
                    $columns[$i] = $key;
                }
            }
        }
        if (! in_array('name', $columns, true)) {
            $errors[] = ['row' => 1, 'message' => 'Kolom "Nama" tidak ditemukan di judul kolom.'];

            return [];
        }

        $rows = [];
        foreach (array_slice($lines, 1) as $n => $line) {
            $cells = str_getcsv($line, $delimiter, '"', '');
            $row = ['_row' => (string) ($n + 2)];
            foreach ($columns as $i => $key) {
                $row[$key] = trim((string) ($cells[$i] ?? ''));
            }
            $rows[] = $row;
        }

        return $rows;
    }

    /** "31/12/1990", "31-12-1990", "1990-12-31" → "1990-12-31". Null bila tidak valid / di masa depan. */
    private function date(string $value): ?string
    {
        $v = trim($value);
        if (preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})$/', $v, $m)) {
            [$y, $mo, $d] = [(int) $m[1], (int) $m[2], (int) $m[3]];
        } elseif (preg_match('#^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$#', $v, $m)) {
            [$d, $mo, $y] = [(int) $m[1], (int) $m[2], (int) $m[3]];
        } else {
            return null;
        }
        if (! checkdate($mo, $d, $y) || $y < 1900) {
            return null;
        }
        $date = sprintf('%04d-%02d-%02d', $y, $mo, $d);

        return $date > now()->toDateString() ? null : $date;
    }
}
