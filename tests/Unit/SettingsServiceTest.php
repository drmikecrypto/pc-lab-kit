<?php

declare(strict_types=1);

use App\Services\SettingsService;

describe('SettingsService', function () {
    test('save and load llm settings from local file', function () {
        $dir = sys_get_temp_dir() . '/pcverse-settings-' . uniqid('', true);
        mkdir($dir . '/storage/settings', 0777, true);
        $svc = new SettingsService($dir);

        $public = $svc->save([
            'llm_api_key' => 'sk-test-key-12345678',
            'llm_base_url' => 'https://api.example.com/v1',
            'llm_model' => 'test-model',
        ]);

        expect($public['ai_configured'])->toBeTrue();
        expect($public['api_key_hint'])->toContain('…');

        $cfg = $svc->llmConfig();
        expect($cfg['api_key'])->toBe('sk-test-key-12345678');
        expect($cfg['base_url'])->toBe('https://api.example.com/v1');
        expect($cfg['model'])->toBe('test-model');

        $cleared = $svc->save(['clear_api_key' => true]);
        expect($cleared['ai_configured'])->toBeFalse();
    });
});
