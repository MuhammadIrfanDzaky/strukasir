@php
    $rp = fn (int $v) => 'Rp'.number_format($v, 0, ',', '.');
    $label = 'font-size:12px;font-weight:700;letter-spacing:0.8px;text-transform:uppercase;color:#475569;';
    $methodTotal = max(1, array_sum(array_column($d['methods'], 'amount')));
    $topMax = max([1, ...array_column($d['top'], 'qty')]);
    $avg = $d['orders'] > 0 ? intdiv($d['sales'], $d['orders']) : 0;
@endphp

{{-- Keterangan shift --}}
<p style="margin:-8px 0 20px;font-size:14px;line-height:1.6;color:#475569;">
  {{ $d['day'] }}, {{ $d['date'] }} · {{ $d['from'] }}–{{ $d['to'] ?? 'sekarang' }}<br>
  Tablet {{ $d['device'] }}@if ($d['outlet']) · {{ $d['outlet'] }}@endif · {{ $d['opened_by'] }}@if ($d['closed_by']) → {{ $d['closed_by'] }}@endif
</p>

{{-- Angka utama --}}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;">
  <tr>
    <td style="padding:18px 20px;">
      <div style="{{ $label }}">Penjualan shift</div>
      <div style="margin-top:4px;font-size:28px;font-weight:800;color:#0F172A;">{{ $rp($d['sales']) }}</div>
    </td>
    <td align="right" style="padding:18px 20px;">
      <div style="font-size:20px;font-weight:700;color:#0F172A;">{{ $d['orders'] }}</div>
      <div style="font-size:12px;color:#475569;">transaksi</div>
      @if ($avg > 0)
      <div style="margin-top:6px;font-size:12px;color:#475569;">rata-rata {{ $rp($avg) }}</div>
      @endif
    </td>
  </tr>
</table>

{{-- Metode bayar: grafik batang --}}
@if ($d['methods'])
<div style="{{ $label }}margin-bottom:8px;">Metode bayar</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;">
  @foreach ($d['methods'] as $i => $x)
  @php $pct = (int) round($x['amount'] * 100 / $methodTotal); @endphp
  <tr>
    <td style="padding:6px 0 2px;font-size:14px;color:#0F172A;">{{ $x['label'] }} <span style="color:#64748B;">· {{ $pct }}%</span></td>
    <td align="right" style="padding:6px 0 2px;font-size:14px;font-weight:600;color:#0F172A;">{{ $rp($x['amount']) }}</td>
  </tr>
  <tr><td colspan="2" style="padding:0 0 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      @if ($pct > 0)<td width="{{ $pct }}%" style="height:8px;background:{{ $i === 0 ? '#3730A3' : '#94A3B8' }};border-radius:4px;font-size:0;line-height:0;">&nbsp;</td>@endif
      @if ($pct < 100)<td style="height:8px;background:#E2E8F0;border-radius:4px;font-size:0;line-height:0;">&nbsp;</td>@endif
    </tr></table>
  </td></tr>
  @endforeach
</table>
@endif

@if (! empty($d['qris']))
<p style="margin:-12px 0 24px;padding:10px 12px;background:#F1F5F9;border-radius:8px;font-size:13px;line-height:1.6;color:#334155;">
  <strong>Cocokkan QRIS:</strong> {{ $d['qris']['count'] }} transaksi {{ $rp($d['qris']['total']) }} dengan mutasi di aplikasi merchant QRIS.@if ($d['qris']['references']) Ref: {{ implode(', ', $d['qris']['references']) }}.@endif @if ($d['qris']['without_reference'] > 0){{ $d['qris']['without_reference'] }} tanpa ref.@endif
</p>
@endif

{{-- Kas laci --}}
@if ($d['cash'] || $d['cash_out'] || $d['cash_in'] || $d['credit_repaid_cash'])
<div style="{{ $label }}margin-bottom:4px;">Kas laci</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;">
  @php
    $rows = [];
    if ($d['cash_in']) $rows['Kas masuk'] = $rp($d['cash_in']);
    if ($d['cash_out']) $rows['Kas keluar'] = $rp($d['cash_out']);
    if ($d['credit_repaid_cash']) $rows['Pelunasan kasbon tunai'] = $rp($d['credit_repaid_cash']);
    if ($d['cash']) { $rows['Seharusnya'] = $rp($d['cash']['expected']); $rows['Dihitung kasir'] = $rp($d['cash']['counted']); }
  @endphp
  @foreach ($rows as $k => $v)
  <tr>
    <td style="padding:8px 0;border-bottom:1px solid #E2E8F0;font-size:14px;color:#475569;">{{ $k }}</td>
    <td align="right" style="padding:8px 0;border-bottom:1px solid #E2E8F0;font-size:14px;font-weight:600;color:#0F172A;">{{ $v }}</td>
  </tr>
  @endforeach
  @if ($d['cash'])
  @php
    $diff = $d['cash']['diff'];
    [$txt, $fg, $bg] = $diff === 0 ? ['Cocok', '#15803D', '#DCFCE7'] : ($diff > 0 ? ['Lebih '.$rp($diff), '#92400E', '#FEF3C7'] : ['Kurang '.$rp(abs($diff)), '#B91C1C', '#FEE2E2']);
  @endphp
  <tr>
    <td style="padding:10px 0;font-size:14px;font-weight:700;color:#0F172A;">Selisih</td>
    <td align="right" style="padding:10px 0;"><span style="display:inline-block;padding:3px 10px;border-radius:999px;background:{{ $bg }};color:{{ $fg }};font-size:13px;font-weight:700;">{{ $txt }}</span></td>
  </tr>
  @endif
</table>
@endif

{{-- Produk terlaris: grafik batang --}}
@if ($d['top'])
<div style="{{ $label }}margin-bottom:8px;">Produk terlaris</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;">
  @foreach ($d['top'] as $i => $t)
  @php $pct = max(4, (int) round($t['qty'] * 100 / $topMax)); @endphp
  <tr>
    <td style="padding:6px 0 2px;font-size:14px;color:#0F172A;">{{ $i + 1 }}. {{ $t['name'] }}</td>
    <td align="right" style="padding:6px 0 2px;font-size:14px;font-weight:600;color:#0F172A;">{{ $t['qty'] }}×</td>
  </tr>
  <tr><td colspan="2" style="padding:0 0 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td width="{{ $pct }}%" style="height:6px;background:{{ $i === 0 ? '#3730A3' : '#94A3B8' }};border-radius:3px;font-size:0;line-height:0;">&nbsp;</td>
      @if ($pct < 100)<td style="height:6px;font-size:0;line-height:0;">&nbsp;</td>@endif
    </tr></table>
  </td></tr>
  @endforeach
</table>
@endif

{{-- Perlu perhatian --}}
@if ($d['voids'] || $d['low_stock'])
<div style="margin:0 0 24px;padding:14px 16px;background:#FEF3C7;border-radius:10px;font-size:14px;line-height:1.6;color:#92400E;">
  @if ($d['voids'])<div><strong>{{ $d['voids'] }} order dibatalkan (void)</strong> di shift ini.</div>@endif
  @if ($d['low_stock'])
  <div><strong>Stok menipis:</strong> {{ collect($d['low_stock'])->take(8)->map(fn ($s) => $s['name'].' '.$s['qty'])->implode(', ') }}@if (count($d['low_stock']) > 8) (+{{ count($d['low_stock']) - 8 }})@endif</div>
  @endif
</div>
@endif

@if ($d['note'])
<div style="{{ $label }}margin-bottom:6px;">Catatan kasir</div>
<p style="margin:0 0 24px;padding-left:12px;border-left:3px solid #E2E8F0;font-size:14px;line-height:1.6;color:#334155;">{{ $d['note'] }}</p>
@endif

{{-- Total hari ini --}}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #E2E8F0;">
  @if ($d['day_outlet'])
  <tr>
    <td style="padding:12px 0 0;font-size:14px;color:#475569;">Hari ini · {{ $d['outlet'] }}</td>
    <td align="right" style="padding:12px 0 0;font-size:14px;font-weight:600;color:#0F172A;">{{ $rp($d['day_outlet']['total']) }} · {{ $d['day_outlet']['n'] }} trx</td>
  </tr>
  @endif
  <tr>
    <td style="padding:12px 0 0;font-size:14px;color:#475569;">Hari ini · {{ $d['all_label'] }}</td>
    <td align="right" style="padding:12px 0 0;font-size:14px;font-weight:700;color:#0F172A;">{{ $rp($d['day_total']['total']) }} · {{ $d['day_total']['n'] }} trx</td>
  </tr>
</table>
