<?php

// static-php-cli runs this at each of its patch points. It applies the php-src
// patch PHP_SRC_PATCH names: a fix upstream published only as source, for a
// line it no longer releases.
if (patch_point() !== 'after-php-extract') {
    return;
}

$patch = getenv('PHP_SRC_PATCH');
if ($patch === false || !is_file($patch)) {
    throw new RuntimeException('PHP_SRC_PATCH names no patch file: ' . var_export($patch, true));
}

$source = SOURCE_PATH . '/php-src';

$applies = function (array $options) use ($patch, $source): bool {
    $process = proc_open(
        ['patch', '-p1', '--batch', '--forward', ...$options],
        [0 => ['file', $patch, 'r'], 1 => STDOUT, 2 => STDERR],
        $pipes,
        $source,
    );
    if ($process === false) {
        throw new RuntimeException('cannot run patch');
    }

    return proc_close($process) === 0;
};

// A retry restores a source tree the first run already patched.
if ($applies(['--reverse', '--dry-run', '--quiet'])) {
    echo "{$patch} is already applied" . PHP_EOL;
    return;
}

if (!$applies(['--dry-run']) || !$applies(['--quiet'])) {
    throw new RuntimeException("{$patch} does not apply to {$source}");
}

echo "applied {$patch}" . PHP_EOL;
