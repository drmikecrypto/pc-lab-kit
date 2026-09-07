<?php

declare(strict_types=1);

use App\Database;
use PHPUnit\Framework\TestCase;

final class DatabaseMigrationTest extends TestCase
{
    protected function setUp(): void
    {
        Database::resetConnection();
    }

    public function testLabJobsMigrationCreatesTable(): void
    {
        $root = dirname(__DIR__, 2);
        $dbPath = $root . '/storage/test-lab-jobs-' . bin2hex(random_bytes(4)) . '.sqlite';
        if (is_file($dbPath)) {
            unlink($dbPath);
        }

        $pdo = new PDO('sqlite:' . $dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

        $sql = (string) file_get_contents($root . '/database/migrations/20260820_lab_jobs.sql');
        $ref = new ReflectionClass(Database::class);
        $split = $ref->getMethod('splitSqlStatements');
        $split->setAccessible(true);
        foreach ($split->invoke(null, $sql) as $stmt) {
            $pdo->exec($stmt);
        }

        $exists = $pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name='lab_jobs'")->fetchColumn();
        $this->assertSame('lab_jobs', $exists);

        unlink($dbPath);
    }
}
