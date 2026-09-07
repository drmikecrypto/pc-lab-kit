<?php

declare(strict_types=1);

require dirname(__DIR__) . '/vendor/autoload.php';

use App\Database;
use App\Support\Env;

Env::load(dirname(__DIR__) . '/.env');
Database::migrate();

echo "Migrations complete.\n";
