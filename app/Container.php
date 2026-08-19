<?php

declare(strict_types=1);

namespace App;

/**
 * Minimal service container for test doubles and thin controllers.
 */
final class Container
{
    /** @var array<string, object> */
    private static array $instances = [];

    /** @var array<string, callable(): object> */
    private static array $factories = [];

    public static function set(string $id, object $instance): void
    {
        self::$instances[$id] = $instance;
    }

    /** @param callable(): object $factory */
    public static function factory(string $id, callable $factory): void
    {
        self::$factories[$id] = $factory;
    }

    public static function get(string $id): object
    {
        if (isset(self::$instances[$id])) {
            return self::$instances[$id];
        }
        if (isset(self::$factories[$id])) {
            self::$instances[$id] = (self::$factories[$id])();

            return self::$instances[$id];
        }

        throw new \RuntimeException("Service not registered: {$id}");
    }

    public static function reset(): void
    {
        self::$instances = [];
        self::$factories = [];
    }
}
