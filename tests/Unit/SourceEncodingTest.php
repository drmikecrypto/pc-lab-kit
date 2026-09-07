<?php

declare(strict_types=1);

/**
 * A UTF-8 BOM before `<?php` makes PHP emit three stray bytes before any header
 * and turns `declare(strict_types=1)` into a fatal error, so sources must stay
 * BOM-free. Some editors re-add the BOM on save, hence this guard.
 */
function pclab_source_files(string $subdir, string $extension): array
{
    $root = dirname(__DIR__, 2) . '/' . $subdir;
    if (!is_dir($root)) {
        return [];
    }

    $found = [];
    $walker = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
    );

    foreach ($walker as $file) {
        if ($file->isFile() && strtolower($file->getExtension()) === $extension) {
            $found[] = $file->getPathname();
        }
    }

    return $found;
}

function pclab_files_with_bom(array $paths): array
{
    $offenders = [];
    foreach ($paths as $path) {
        $handle = fopen($path, 'rb');
        if ($handle === false) {
            continue;
        }
        $head = (string) fread($handle, 3);
        fclose($handle);

        if ($head === "\xEF\xBB\xBF") {
            $offenders[] = $path;
        }
    }

    return $offenders;
}

test('php sources carry no utf-8 bom', function () {
    $paths = [];
    foreach (['app', 'config', 'routes', 'resources', 'tests', 'public', 'bin', 'cron'] as $dir) {
        $paths = array_merge($paths, pclab_source_files($dir, 'php'));
    }

    expect($paths)->not->toBeEmpty();
    expect(pclab_files_with_bom($paths))->toBe([]);
});

test('layout template opens with php tag then strict types', function () {
    $layout = dirname(__DIR__, 2) . '/resources/views/layout.php';
    $head = (string) file_get_contents($layout, false, null, 0, 64);

    expect(str_starts_with($head, '<?php'))->toBeTrue();
    expect($head)->toContain('declare(strict_types=1);');
});
