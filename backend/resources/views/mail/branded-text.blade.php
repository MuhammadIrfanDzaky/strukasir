@if ($m['title'])
{!! $m['title'] !!}

@endif
@if ($m['greeting'])
{!! $m['greeting'] !!}

@endif
@foreach ($m['intro'] as $p)
{!! $p !!}

@endforeach
@if ($m['text'])
{!! $m['text'] !!}

@endif
@if ($m['code'])
    {!! $m['code'] !!}

@endif
@if ($m['box'])
{!! $m['box']['label'] !!}: {!! $m['box']['value'] !!}
@if (! empty($m['box']['caption']))
{!! $m['box']['caption'] !!}
@endif

@endif
@foreach ($m['rows'] as $label => $value)
{!! $label !!}: {!! $value !!}
@endforeach
@if ($m['rows'])

@endif
@foreach ($m['steps'] as $i => $step)
{{ $i + 1 }}. {!! $step !!}
@endforeach
@if ($m['steps'])

@endif
@if ($m['button'])
{!! $m['button'][0] !!}: {!! $m['button'][1] !!}

@endif
@foreach ($m['outro'] as $p)
{!! $p !!}

@endforeach
@if ($m['note'])
{!! $m['note'] !!}

@endif
— Strukasir
@if ($m['reason'])
{!! $m['reason'] !!}
@endif
