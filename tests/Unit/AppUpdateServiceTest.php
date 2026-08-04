<?php

declare(strict_types=1);

use App\Services\AppUpdateService;

test('app update version compare treats equal as not newer', function () {
    $svc = new AppUpdateService();
    expect($svc->versionIsNewer('3.1.0', '3.1.0'))->toBeFalse()
        ->and($svc->versionIsNewer('3.0.0', '3.1.0'))->toBeFalse()
        ->and($svc->versionIsNewer('3.2.0', '3.1.0'))->toBeTrue()
        ->and($svc->versionIsNewer('10.0.0', '9.9.9'))->toBeTrue();
});

test('app update finalize sets update_available from fixture payload', function () {
    $svc = new AppUpdateService();
    $available = $svc->finalizePayload([
        'ok' => true,
        'latest_version' => '9.9.9',
        'release_url' => 'https://example.test/release',
        'download_windows' => 'https://example.test/win.exe',
        'download_linux' => 'https://example.test/linux.AppImage',
    ], '3.1.0');

    expect($available['current_version'])->toBe('3.1.0')
        ->and($available['latest_version'])->toBe('9.9.9')
        ->and($available['update_available'])->toBeTrue();

    $same = $svc->finalizePayload([
        'ok' => true,
        'latest_version' => '3.1.0',
    ], '3.1.0');

    expect($same['update_available'])->toBeFalse();
});

test('app update check uses injectable release fetcher', function () {
    $svc = new AppUpdateService(fn () => [
        'version' => '99.0.0',
        'name' => 'PC Lab Kit 99.0.0',
        'url' => 'https://example.test/r',
        'published_at' => '2026-01-01T00:00:00Z',
        'notes' => 'Fixture release',
        'download_windows' => 'https://example.test/win.exe',
        'download_linux' => 'https://example.test/linux.AppImage',
        'download_probe' => 'https://example.test/probe.zip',
    ]);

    $out = $svc->check(true);

    expect($out['ok'])->toBeTrue()
        ->and($out['latest_version'])->toBe('99.0.0')
        ->and($out['update_available'])->toBeTrue()
        ->and($out['download_windows'])->toBe('https://example.test/win.exe');
});

test('app update check reports failure when fetcher returns null', function () {
    $svc = new AppUpdateService(fn () => null);
    $out = $svc->check(true);

    expect($out['ok'])->toBeFalse()
        ->and($out['update_available'])->toBeFalse()
        ->and($out['message'])->toContain('GitHub');
});
