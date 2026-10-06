<?php

namespace Tests\Unit;

use Tests\TestCase;

/** Pelacak error tidak boleh mengirim data pribadi atau isi request (password, PIN, kode 2FA). */
class SentryConfigTest extends TestCase
{
    public function test_privacy_options_are_locked(): void
    {
        $this->assertFalse(config('sentry.send_default_pii'));
        $this->assertSame('never', config('sentry.max_request_body_size'));
        $this->assertFalse((bool) config('sentry.breadcrumbs.sql_bindings'));
    }

    public function test_disabled_without_dsn(): void
    {
        $this->assertEmpty(config('sentry.dsn'));
    }
}
