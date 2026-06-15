<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Services\SettingsService;

class SettingsApiController
{
    public function get(): string
    {
        return json_response((new SettingsService())->publicSettings());
    }

    public function save(): string
    {
        $input = decode_json_body_limited(65536);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Request too large.'], 413);
        }
        if ($input === []) {
            return json_response(['ok' => false, 'message' => 'Empty request.'], 400);
        }

        try {
            $settings = (new SettingsService())->save($input);

            return json_response(array_merge(['ok' => true], $settings));
        } catch (\InvalidArgumentException $e) {
            return json_response(['ok' => false, 'message' => 'Invalid settings. Check the API URL.'], 422);
        } catch (\Throwable $e) {
            error_log('settings save: ' . $e->getMessage());

            return json_response(['ok' => false, 'message' => 'Could not save settings.'], 500);
        }
    }
}
