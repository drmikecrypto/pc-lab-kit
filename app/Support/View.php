<?php

declare(strict_types=1);

namespace App\Support;

class View
{
    protected string $name;
    protected array $data;

    public function __construct(string $name, array $data = [])
    {
        $this->name = $name;
        $this->data = $data;
    }

    public static function make(string $name, array $data = []): self
    {
        return new self($name, $data);
    }

    public function render(): string
    {
        $config = require dirname(__DIR__, 2) . '/config/app.php';
        $data = array_merge([
            'config' => $config,
            'title' => 'PCVerse',
            'settings' => [],
            'footer_minimal' => false,
        ], $this->data);

        extract($data);

        $viewPath = dirname(__DIR__, 2) . "/resources/views/{$this->name}.php";
        ob_start();
        if (is_file($viewPath)) {
            include $viewPath;
        } else {
            echo "View [{$this->name}] not found.";
        }
        $content = ob_get_clean();

        ob_start();
        $layoutPath = dirname(__DIR__, 2) . '/resources/views/layout.php';
        if (is_file($layoutPath)) {
            include $layoutPath;
        } else {
            echo $content;
        }

        return ob_get_clean();
    }
}
