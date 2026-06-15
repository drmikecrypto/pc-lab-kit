<?php

declare(strict_types=1);

namespace App;

final class Router
{
    /** @var list<array{method: string, pattern: string, regex: string, keys: list<string>, handler: callable}> */
    private array $routes = [];

    public function get(string $pattern, callable $handler): void
    {
        $this->add('GET', $pattern, $handler);
    }

    public function post(string $pattern, callable $handler): void
    {
        $this->add('POST', $pattern, $handler);
    }

    private function add(string $method, string $pattern, callable $handler): void
    {
        $keys = [];
        $regex = preg_replace_callback('/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/', function ($m) use (&$keys) {
            $keys[] = $m[1];

            return '([^/]+)';
        }, $pattern);
        $regex = '#^' . $regex . '$#';

        $this->routes[] = [
            'method' => strtoupper($method),
            'pattern' => $pattern,
            'regex' => $regex,
            'keys' => $keys,
            'handler' => $handler,
        ];
    }

    public function dispatch(string $method, string $path): void
    {
        $method = strtoupper($method);
        $path = rtrim($path, '/') ?: '/';

        foreach ($this->routes as $route) {
            if ($route['method'] !== $method) {
                continue;
            }
            if (!preg_match($route['regex'], $path, $matches)) {
                continue;
            }

            $args = [];
            foreach ($route['keys'] as $key) {
                $args[] = $matches[$key] ?? '';
            }

            $result = ($route['handler'])(...$args);
            if (is_string($result)) {
                echo $result;
            }

            return;
        }

        http_response_code(404);
        echo view('errors/404', ['title' => 'Not found']);
    }
}
