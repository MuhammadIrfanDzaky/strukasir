-- Role aplikasi SENGAJA bukan superuser: superuser selalu menembus Row-Level Security.
CREATE ROLE berrybrew_app LOGIN PASSWORD 'berrybrew' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE berrybrew OWNER berrybrew_app;
CREATE DATABASE berrybrew_test OWNER berrybrew_app;
