<?php

namespace App\Support\Database;

use Illuminate\Support\Facades\DB;

/**
 * Helper migrasi untuk isolasi tenant di level database (PostgreSQL Row-Level Security).
 *
 * Lapis kedua di bawah global scope Eloquent: query apa pun (termasuk DB::table / raw SQL)
 * hanya melihat baris milik tenant di `app.tenant_id`. Role aplikasi harus non-superuser,
 * karena superuser selalu menembus RLS.
 */
class Rls
{
    public static function enable(string $table): void
    {
        $predicate = "current_setting('app.bypass_rls', true) = 'on'"
            ." OR tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid";

        DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");
        DB::statement("ALTER TABLE {$table} FORCE ROW LEVEL SECURITY");
        DB::statement("CREATE POLICY tenant_isolation ON {$table} USING ({$predicate}) WITH CHECK ({$predicate})");
    }

    /**
     * Tabel append-only: UPDATE/DELETE ditolak database. Koreksi dicatat sebagai baris baru.
     * Pengecualian hanya untuk offboarding tenant (`app.allow_purge = on`).
     */
    public static function appendOnly(string $table): void
    {
        DB::statement(<<<'SQL'
            CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger AS $$
            BEGIN
                IF current_setting('app.allow_purge', true) = 'on' THEN
                    RETURN COALESCE(OLD, NEW);
                END IF;
                RAISE EXCEPTION '% is append-only (% not allowed)', TG_TABLE_NAME, TG_OP;
            END;
            $$ LANGUAGE plpgsql
        SQL);

        DB::statement("CREATE TRIGGER {$table}_append_only BEFORE UPDATE OR DELETE ON {$table}"
            .' FOR EACH ROW EXECUTE FUNCTION forbid_mutation()');
    }
}
