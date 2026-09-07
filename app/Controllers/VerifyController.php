<?php

declare(strict_types=1);

namespace App\Controllers;

class VerifyController
{
    public function show(string $hash): string
    {
        $hash = strtolower(trim($hash));
        $valid = false;
        $session = null;
        if (preg_match('/^[a-f0-9]{64}$/', $hash)) {
            $svc = new \App\Services\LabSessionService();
            $valid = $svc->verifyHash($hash);
            if ($valid) {
                $dir = dirname(__DIR__, 2) . '/storage/sessions';
                foreach (glob($dir . '/*.pclab.json') ?: [] as $path) {
                    $data = json_decode((string) file_get_contents($path), true);
                    if (is_array($data) && hash_equals($hash, (string) ($data['session_hash'] ?? ''))) {
                        $session = $data;
                        break;
                    }
                }
            }
        }

        return view('verify', [
            'title' => 'PC Lab Kit — Certificate Verify',
            'document_title' => 'Verify certificate',
            'hash' => $hash,
            'valid' => $valid,
            'session' => $session,
        ]);
    }

    /** Offline verify of an uploaded / posted .pclab JSON body. */
    public function verifyPayload(): string
    {
        $input = decode_json_body_limited(4_000_000) ?? [];
        $json = (string) ($input['json'] ?? '');
        if ($json === '' && isset($input['format'])) {
            $json = json_encode($input, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '';
        }
        try {
            $svc = new \App\Services\LabSessionService();
            $session = $svc->import($json);
            $offline = $svc->verifyPayload($session);

            return json_response([
                'ok' => true,
                'verified' => !empty($session['verified']) && $offline,
                'session' => $session,
            ]);
        } catch (\Throwable $e) {
            return json_response(['ok' => false, 'error' => 'verify_failed', 'message' => 'Could not verify certificate payload.'], 400);
        }
    }
}
