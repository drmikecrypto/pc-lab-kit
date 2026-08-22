<?php

declare(strict_types=1);

use App\Services\ProbeAuthService;
use App\Services\ShopFleetService;
use App\Support\RateLimit;

describe('Hardening', function () {
    test('csrf_token creates and returns session token', function () {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }
        $_SESSION = [];
        session_id('pclab-test-csrf-' . uniqid());
        session_start();
        unset($_SESSION['pclab_csrf']);
        $a = csrf_token();
        $b = csrf_token();
        expect($a)->not->toBe('')
            ->and($a)->toBe($b)
            ->and(strlen($a))->toBe(32);
        session_write_close();
    });

    test('require_csrf accepts matching header in CLI', function () {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }
        session_id('pclab-test-csrf2-' . uniqid());
        session_start();
        $_SESSION['pclab_csrf'] = 'abcdef0123456789abcdef0123456789';
        $_SERVER['HTTP_X_CSRF_TOKEN'] = 'abcdef0123456789abcdef0123456789';
        expect(require_csrf())->toBeTrue();
        $_SERVER['HTTP_X_CSRF_TOKEN'] = 'wrong';
        expect(require_csrf())->toBeFalse();
        session_write_close();
    });

    test('ProbeAuthService reads token file override', function () {
        $dir = sys_get_temp_dir() . '/pclab-probe-auth-' . uniqid('', true);
        mkdir($dir, 0777, true);
        $file = $dir . '/auth.token';
        file_put_contents($file, "secret-token-xyz\n");
        $svc = new ProbeAuthService();
        // Clear env for this process if set
        $prev = getenv('PCLAB_PROBE_TOKEN');
        putenv('PCLAB_PROBE_TOKEN');
        $resolved = $svc->resolve($file);
        if ($prev !== false) {
            putenv('PCLAB_PROBE_TOKEN=' . $prev);
        }
        expect($resolved['token'])->toBe('secret-token-xyz')
            ->and($resolved['auth_required'])->toBeTrue()
            ->and($resolved['source'])->toBe('file');
        expect($svc->isLoopbackProbeBase('http://127.0.0.1:18765'))->toBeTrue();
        expect($svc->isLoopbackProbeBase('http://evil.example:18765'))->toBeFalse();
    });

    test('ShopFleetService allowlists loopback probe_base only', function () {
        $svc = new ShopFleetService();
        expect($svc->allowlistProbeBase('http://127.0.0.1:18765'))->toBe('http://127.0.0.1:18765');
        expect($svc->allowlistProbeBase('http://localhost:18765'))->toBe('http://127.0.0.1:18765');
        expect($svc->allowlistProbeBase('http://192.168.1.10:18765'))->toBeNull();
        expect($svc->allowlistProbeBase('http://127.0.0.1:9999'))->toBeNull();
        expect($svc->allowlistProbeBase('http://127.0.0.1:18761', 5))->toBe('http://127.0.0.1:18761');
    });

    test('RateLimit allows then blocks after max', function () {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }
        session_id('pclab-rl-' . uniqid());
        session_start();
        $bucket = 'test_bucket_' . uniqid();
        expect(RateLimit::attempt($bucket, 2))->toBeTrue();
        expect(RateLimit::attempt($bucket, 2))->toBeTrue();
        expect(RateLimit::attempt($bucket, 2))->toBeString();
        session_write_close();
    });
});
