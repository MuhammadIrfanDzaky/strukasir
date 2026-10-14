<?php

namespace Tests\Feature;

use App\Mail\PaymentReceiptMail;
use App\Mail\PlanReminderMail;
use App\Mail\ReferralRewardMail;
use App\Mail\SecurityAlertMail;
use App\Mail\ShiftReportMail;
use App\Mail\WelcomeMail;
use App\Models\Plan;
use App\Models\Tenant;
use App\Services\SubscriptionService;
use App\Support\PlanCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Tests\TestCase;

class EmailNotificationsTest extends TestCase
{
    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        PlanCatalog::sync();
        Mail::fake();
        $this->shop = $this->makeShop('BerryBrew');
        $this->shop->owner->forceFill(['email' => 'owner@berrybrew.test', 'password' => 'rahasia123'])->save();
    }

    private function signup(string $email, array $override = [])
    {
        DB::table('signup_codes')->insert([
            'id' => (string) Str::uuid7(), 'email' => $email, 'code_hash' => Hash::make('135790'),
            'expires_at' => now()->addMinutes(15), 'created_at' => now()->subMinutes(5),
        ]);

        return $this->postJson('/api/v1/signup', [
            'owner_name' => 'Wahyu', 'email' => $email, 'email_code' => '135790', 'password' => 'rahasia123', 'pin' => '482915',
            'business_name' => 'Laundry Bersih', 'sector' => 'laundry', 'province_code' => '12', 'regency_code' => '12.71',
            'terms' => true, 'device_id' => (string) Str::uuid(), ...$override,
        ])->assertCreated();
    }

    public function test_semua_email_memakai_template_bermerek_dengan_versi_teks(): void
    {
        $mails = [
            new ShiftReportMail('Laporan shift', "*Laporan shift BerryBrew*\nPenjualan: Rp60.000"),
            new PaymentReceiptMail('Wahyu', 'BerryBrew', 'Tumbuh', 'quarter', 67200, 25, 'referred', 50400, now()->addMonths(3), 'STK-ABC', now()),
            new WelcomeMail('Wahyu', 'BerryBrew', 'Gratis', true, now()->addDays(7), 'K7M2PQ'),
            new PlanReminderMail('Wahyu', 'BerryBrew', 'Gratis', 'trial', now()->addDay(), 1),
            new PlanReminderMail('Wahyu', 'BerryBrew', 'Tumbuh', 'active', now()->subHour(), 0),
            new ReferralRewardMail('Wahyu', 'Laundry Bersih', 50, 2),
            new SecurityAlertMail('Wahyu', 'BerryBrew', SecurityAlertMail::DEVICE_ADDED, now(), ['Tablet' => 'Tablet 2 (T2)']),
        ];
        foreach ($mails as $mail) {
            $mail->assertSeeInHtml('STRUKASIR');
            $mail->assertSeeInText('Strukasir');
        }
        $mails[0]->assertSeeInText('Penjualan: Rp60.000')->assertDontSeeInText('*');
        $mails[1]->assertSeeInHtml('Rp50.400')->assertSeeInHtml('Diskon referral 25%')->assertSeeInHtml('3 bulan');
        $mails[2]->assertSeeInText('K7M2PQ');
        $mails[3]->assertSeeInHtml('berakhir besok');
        $mails[0]->assertSeeInHtml('Laporan shift BerryBrew');
        $this->assertStringContainsString('sudah berakhir', $mails[4]->envelope()->subject);
    }

    public function test_daftar_mengirim_email_selamat_datang(): void
    {
        $this->signup('baru@contoh.id');

        Mail::assertSent(WelcomeMail::class, fn (WelcomeMail $m) => $m->hasTo('baru@contoh.id')
            && $m->businessName === 'Laundry Bersih' && $m->free && $m->referralCode !== null);
        Mail::assertNotSent(SecurityAlertMail::class); // tablet pertama saat daftar bukan peringatan
    }

    public function test_paket_lunas_mengirim_kuitansi_dan_kupon_ke_pengajak(): void
    {
        $friend = Tenant::findOrFail($this->signup('baru@contoh.id', ['referral_code' => $this->shop->tenant->refresh()->referral_code])->json('tenant.id'));

        app(SubscriptionService::class)->activate($friend, Plan::where('code', 'tumbuh')->firstOrFail(), 'month');

        Mail::assertSent(PaymentReceiptMail::class, fn (PaymentReceiptMail $m) => $m->hasTo('baru@contoh.id')
            && $m->amount === 18700 && $m->discountPercent === 25 && str_starts_with($m->receiptNo, 'STK-'));
        Mail::assertSent(ReferralRewardMail::class, fn (ReferralRewardMail $m) => $m->hasTo('owner@berrybrew.test')
            && $m->refereeName === 'Laundry Bersih' && $m->available === 1);
    }

    public function test_tablet_baru_dan_reset_password_mengirim_peringatan_keamanan(): void
    {
        $this->postJson('/api/v1/devices/register', ['email' => 'owner@berrybrew.test', 'password' => 'rahasia123', 'device_id' => (string) Str::uuid()])
            ->assertCreated();
        Mail::assertSent(SecurityAlertMail::class, fn (SecurityAlertMail $m) => $m->hasTo('owner@berrybrew.test')
            && $m->kind === SecurityAlertMail::DEVICE_ADDED && str_contains($m->details['Tablet'], 'T2'));

        $this->artisan('pos:reset-owner-password', ['email' => 'owner@berrybrew.test'])->assertSuccessful();
        Mail::assertSent(SecurityAlertMail::class, fn (SecurityAlertMail $m) => $m->kind === SecurityAlertMail::PASSWORD_CHANGED);
    }

    public function test_pengingat_paket_terkirim_sekali_per_tahap(): void
    {
        $tenant = $this->shop->tenant->refresh();
        $tenant->plan_id = Plan::where('code', 'gratis')->value('id');
        $tenant->plan_status = 'trial';
        $tenant->plan_ends_at = now()->addHours(60);
        $tenant->save();

        $this->artisan('pos:plan-reminders')->assertSuccessful();
        $this->artisan('pos:plan-reminders')->assertSuccessful(); // jalan ulang: tidak dobel
        Mail::assertSent(PlanReminderMail::class, 1);
        Mail::assertSent(PlanReminderMail::class, fn (PlanReminderMail $m) => $m->daysLeft === 3);

        $this->travel(2)->days();
        $this->artisan('pos:plan-reminders');
        Mail::assertSent(PlanReminderMail::class, fn (PlanReminderMail $m) => $m->daysLeft === 1);

        $this->travel(1)->days();
        $this->artisan('pos:plan-reminders');
        Mail::assertSent(PlanReminderMail::class, fn (PlanReminderMail $m) => $m->daysLeft === 0);
        Mail::assertSent(PlanReminderMail::class, 3);
    }
}
