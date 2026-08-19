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
}
