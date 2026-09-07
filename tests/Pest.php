<?php

declare(strict_types=1);

use App\Database;
use App\Support\Env;

Env::load(dirname(__DIR__) . '/.env');
$_ENV['DB_SQLITE_PATH'] = 'storage/database/test.sqlite';
putenv('DB_SQLITE_PATH=storage/database/test.sqlite');

pest()->in('Unit');

beforeEach(function () {
    Database::resetConnection();
    $path = dirname(__DIR__) . '/storage/database/test.sqlite';
    if (is_file($path)) {
        unlink($path);
    }
    Database::migrate();
});
