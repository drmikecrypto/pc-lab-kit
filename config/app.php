<?php

declare(strict_types=1);

use App\Support\Env;

return [
    'name' => Env::get('APP_NAME', 'PCVerse'),
    'name_en' => 'PCVerse',
    'version' => Env::get('APP_VERSION', '1.0.0'),
    'tagline' => 'Local PC laboratory — probe, test, monitor, tune.',
    'url' => rtrim(Env::get('APP_URL', 'http://127.0.0.1:8080'), '/'),
    'debug' => filter_var(Env::get('APP_DEBUG', 'true'), FILTER_VALIDATE_BOOLEAN),
    'brand_logo_path' => '/assets/img/pc-lab-kit.svg',
    'db' => [
        'driver' => Env::get('DB_DRIVER', 'sqlite'),
        'sqlite_path' => dirname(__DIR__) . '/' . ltrim(Env::get('DB_SQLITE_PATH', 'storage/database/pcverse.sqlite'), '/'),
    ],
    'exchange' => [
        'fallback_usdt_toman' => 200_000,
        'cache_ttl_seconds' => 604_800,
        'wallex_markets_url' => 'https://api.wallex.ir/v1/markets',
    ],
    'llm' => [
        'api_key' => Env::get('LLM_API_KEY', Env::get('OPENAI_API_KEY', '')),
        'base_url' => Env::get('LLM_BASE_URL', 'https://api.openai.com/v1'),
        'model' => Env::get('LLM_MODEL', 'gpt-4o-mini'),
        'timeout_seconds' => (float) Env::get('LLM_TIMEOUT_SECONDS', '120'),
    ],
    'github' => [
        'owner' => Env::get('GITHUB_OWNER', 'drmikecrypto'),
        'repo' => Env::get('GITHUB_REPO', 'pc-lab-kit'),
        'profile_url' => 'https://github.com/drmikecrypto',
    ],
];
