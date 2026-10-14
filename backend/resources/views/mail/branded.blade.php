{{-- Template email Strukasir. Gaya inline & tabel (didukung Gmail/Outlook), tanpa gambar eksternal. --}}
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>{{ $m['subject'] }}</title>
</head>
<body style="margin:0;padding:0;background:#F1F5F9;font-family:'Plus Jakarta Sans',-apple-system,'Segoe UI',Roboto,Arial,sans-serif;color:#0F172A;">
@if ($m['preheader'])
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">{{ $m['preheader'] }}</div>
@endif
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F1F5F9;">
<tr><td align="center" style="padding:32px 16px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
    {{-- Merek --}}
    <tr><td style="padding:0 4px 16px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="background:#3730A3;color:#FFFFFF;font-weight:800;font-size:18px;line-height:32px;width:32px;text-align:center;border-radius:6px;">S<span style="color:#F59E0B;">.</span></td>
        <td style="padding-left:10px;font-weight:800;font-size:18px;letter-spacing:0.5px;color:#0F172A;">STRUKASIR</td>
      </tr></table>
    </td></tr>

    {{-- Kartu isi --}}
    <tr><td style="background:#FFFFFF;border:1px solid #E2E8F0;border-radius:12px;padding:32px 28px;">
      @if ($m['title'])
      <h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;font-weight:700;color:#0F172A;">{{ $m['title'] }}</h1>
      @endif
      @if ($m['greeting'])
      <p style="margin:0 0 12px;font-size:15px;line-height:1.6;">{{ $m['greeting'] }}</p>
      @endif
      @foreach ($m['intro'] as $p)
      <p style="margin:0 0 12px;font-size:15px;line-height:1.6;color:#334155;">{{ $p }}</p>
      @endforeach

      @if ($m['text'])
      <div style="margin:16px 0;padding:16px 18px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;font-size:14px;line-height:1.7;color:#0F172A;white-space:pre-line;">{{ $m['text'] }}</div>
      @endif

      @if ($m['code'])
      <div style="margin:20px 0;padding:18px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;text-align:center;font-size:32px;font-weight:800;letter-spacing:8px;color:#0F172A;">{{ $m['code'] }}</div>
      @endif

      @if ($m['box'])
      <div style="margin:20px 0;padding:16px 18px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:10px;">
        <div style="font-size:12px;font-weight:700;letter-spacing:0.8px;text-transform:uppercase;color:#475569;">{{ $m['box']['label'] }}</div>
        <div style="margin-top:4px;font-size:20px;font-weight:700;color:#0F172A;">{{ $m['box']['value'] }}</div>
        @if (! empty($m['box']['caption']))
        <div style="margin-top:4px;font-size:13px;color:#475569;">{{ $m['box']['caption'] }}</div>
        @endif
      </div>
      @endif

      @if ($m['rows'])
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:16px 0;border-top:1px solid #E2E8F0;">
        @foreach ($m['rows'] as $label => $value)
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #E2E8F0;font-size:14px;color:#475569;">{{ $label }}</td>
          <td align="right" style="padding:10px 0;border-bottom:1px solid #E2E8F0;font-size:14px;font-weight:600;color:#0F172A;">{{ $value }}</td>
        </tr>
        @endforeach
      </table>
      @endif

      @if ($m['steps'])
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:12px 0;">
        @foreach ($m['steps'] as $i => $step)
        <tr>
          <td valign="top" style="width:28px;padding:6px 0;font-size:14px;font-weight:700;color:#3730A3;">{{ $i + 1 }}.</td>
          <td style="padding:6px 0;font-size:15px;line-height:1.5;color:#334155;">{{ $step }}</td>
        </tr>
        @endforeach
      </table>
      @endif

      @if ($m['button'])
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin:20px 0;"><tr>
        <td style="background:#3730A3;border-radius:8px;">
          <a href="{{ $m['button'][1] }}" style="display:inline-block;padding:12px 22px;font-size:15px;font-weight:700;color:#FFFFFF;text-decoration:none;">{{ $m['button'][0] }}</a>
        </td>
      </tr></table>
      @endif

      @foreach ($m['outro'] as $p)
      <p style="margin:0 0 12px;font-size:15px;line-height:1.6;color:#334155;">{{ $p }}</p>
      @endforeach

      @if ($m['note'])
      <p style="margin:20px 0 0;padding-top:16px;border-top:1px solid #E2E8F0;font-size:13px;line-height:1.6;color:#64748B;">{{ $m['note'] }}</p>
      @endif
    </td></tr>

    {{-- Kaki --}}
    <tr><td style="padding:16px 4px 0;font-size:12px;line-height:1.6;color:#64748B;">
      @if ($m['reason'])
      {{ $m['reason'] }}<br>
      @endif
      Strukasir · Kasir, struk, dan laporan untuk usaha Anda.
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>
