<?php

// static-php-cli runs this at each of its patch points. The ICU it builds
// intl against on Windows needs C++17, which PHP's intl build asks for only
// from 8.4; before that it is added to the same flags, as 8.4 does.
if (patch_point() !== 'after-php-extract') {
    return;
}

$config = SOURCE_PATH . '/php-src/ext/intl/config.w32';
$text = file_get_contents($config);
if ($text === false) {
    throw new RuntimeException("cannot read {$config}");
}

if (str_contains($text, '/std:c++17')) {
    return;
}

$patched = str_replace(
    'ADD_FLAG("CFLAGS_INTL", "/EHsc ',
    'ADD_FLAG("CFLAGS_INTL", "/std:c++17 /EHsc ',
    $text,
    $count,
);
if ($count !== 1) {
    throw new RuntimeException("{$config} has no CFLAGS_INTL line to add C++17 to");
}

file_put_contents($config, $patched);
