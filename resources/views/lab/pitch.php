<?php
/** @var string $title */
/** @var string $meta_description */
/** @var string $heading */
/** @var string $lead */
/** @var list<string> $benefits */
/** @var string $primary_href */
/** @var string $primary_label */
/** @var string $secondary_href */
/** @var string $secondary_label */
/** @var string $sibling_href */
/** @var string $sibling_label */
/** @var string $theme */
/** @var string|null $closing */
/** @var string $slug */
$closing = $closing ?? null;
$themeClass = $theme === 'violet' ? 'lab-pitch--violet' : 'lab-pitch--cyan';
$iconSvg = $theme === 'violet'
    ? '<svg class="lab-pitch__icon-svg" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/></svg>'
    : '<svg class="lab-pitch__icon-svg" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/></svg>';
?>
<link rel="stylesheet" href="/assets/css/lab-pitch.css?v=1.2.0">
<section class="lab-pitch <?= e($themeClass) ?>" data-lab="<?= e($slug) ?>">
    <div class="lab-pitch__shell">
        <a href="/diagnostic" class="lab-pitch__back">← Back to lab</a>

        <div class="lab-pitch__card">
            <div class="lab-pitch__card-head">
                <div class="lab-pitch__card-copy">
                    <h1 class="lab-pitch__title"><?= e($heading) ?></h1>
                    <p class="lab-pitch__lead"><?= e($lead) ?></p>
                </div>
                <span class="lab-pitch__icon"><?= $iconSvg ?></span>
            </div>

            <ul class="lab-pitch__list">
                <?php foreach ($benefits as $item): ?>
                <li><?= e($item) ?></li>
                <?php endforeach; ?>
            </ul>

            <?php if ($closing !== null && $closing !== ''): ?>
            <p class="lab-pitch__closing"><?= e($closing) ?></p>
            <?php endif; ?>

            <div class="lab-pitch__actions">
                <a href="<?= e($primary_href) ?>" class="lab-pitch__btn"><?= e($primary_label) ?></a>
                <a href="<?= e($secondary_href) ?>" class="lab-pitch__sibling"><?= e($secondary_label) ?></a>
            </div>
            <p class="lab-pitch__more"><a href="<?= e($sibling_href) ?>"><?= e($sibling_label) ?></a></p>
        </div>
    </div>
</section>
