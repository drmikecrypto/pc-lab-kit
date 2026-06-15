<?php

declare(strict_types=1);

namespace App;

use PDO;
use PDOException;

class Database
{
    private static ?PDO $pdo = null;

    public static function usesMysqlDialect(): bool
    {
        return false;
    }

    public static function resetConnection(): void
    {
        self::$pdo = null;
    }

    public static function connection(): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }

        $config = require dirname(__DIR__) . '/config/app.php';
        $db = $config['db'];
        $path = (string) ($db['sqlite_path'] ?? '');
        $dir = dirname($path);
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }

        self::$pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);

        return self::$pdo;
    }

    public static function migrate(): void
    {
        $pdo = self::connection();
        $pdo->exec('CREATE TABLE IF NOT EXISTS migrations (migration VARCHAR(255) PRIMARY KEY)');

        $dir = dirname(__DIR__) . '/database/migrations';
        if (!is_dir($dir)) {
            return;
        }

        $files = glob($dir . '/*.sql') ?: [];
        sort($files);

        foreach ($files as $file) {
            if (!is_file($file)) {
                continue;
            }
            $name = basename($file);
            $chk = $pdo->prepare('SELECT COUNT(*) FROM migrations WHERE migration = ?');
            $chk->execute([$name]);
            if ((int) $chk->fetchColumn() > 0) {
                continue;
            }

            $sql = (string) file_get_contents($file);
            $sql = str_replace('AUTO_INCREMENT', '', $sql);
            $sql = preg_replace('/\bINSERT\s+IGNORE\b/i', 'INSERT OR IGNORE', $sql) ?? $sql;

            foreach (array_filter(array_map('trim', explode(';', $sql))) as $stmt) {
                if ($stmt === '' || str_starts_with($stmt, '--')) {
                    continue;
                }
                try {
                    $pdo->exec($stmt);
                } catch (PDOException $e) {
                    if (!self::isIgnorable($e)) {
                        throw $e;
                    }
                }
            }

            $pdo->prepare('INSERT INTO migrations (migration) VALUES (?)')->execute([$name]);
        }
    }

    private static function isIgnorable(PDOException $e): bool
    {
        $msg = $e->getMessage();

        return str_contains($msg, 'duplicate column')
            || str_contains($msg, 'already exists');
    }
}
