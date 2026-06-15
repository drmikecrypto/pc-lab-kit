<?php

declare(strict_types=1);

/** @deprecated Use DiagnosticGameCatalogService / cron/refresh_diagnostic_games.php */

$titles = [
    'Cyberpunk 2077', 'Red Dead Redemption 2', 'Elden Ring', 'Baldur\'s Gate 3', 'Starfield',
    'Hogwarts Legacy', 'Call of Duty: Modern Warfare III', 'Call of Duty: Warzone', 'Fortnite', 'Apex Legends',
    'Valorant', 'Counter-Strike 2', 'Dota 2', 'League of Legends', 'Overwatch 2',
    'PUBG: Battlegrounds', 'Rainbow Six Siege', 'Destiny 2', 'GTA V', 'GTA Online',
    'Minecraft', 'Roblox', 'Rust', 'ARK: Survival Ascended', 'Palworld',
    'Helldivers 2', 'Monster Hunter Wilds', 'Black Myth: Wukong', 'Final Fantasy XVI', 'Final Fantasy XIV',
    'World of Warcraft', 'Diablo IV', 'Path of Exile', 'Path of Exile 2', 'Lost Ark',
    'New World', 'The Finals', 'XDefiant', 'Battlefield 2042', 'Battlefield V',
    'Assassin\'s Creed Mirage', 'Assassin\'s Creed Valhalla', 'Far Cry 6', 'Watch Dogs: Legion', 'Tom Clancy\'s The Division 2',
    'Forza Horizon 5', 'Forza Motorsport', 'Gran Turismo 7', 'F1 24', 'Assetto Corsa Competizione',
    'Euro Truck Simulator 2', 'American Truck Simulator', 'Microsoft Flight Simulator', 'DCS World', 'War Thunder',
    'World of Tanks', 'Warframe', 'Genshin Impact', 'Honkai: Star Rail', 'Zenless Zone Zero',
    'Star Wars Jedi: Survivor', 'Star Wars Battlefront II', 'Mass Effect Legendary Edition', 'Dragon Age: Veilguard', 'The Witcher 3',
    'Horizon Forbidden West', 'God of War', 'Spider-Man Remastered', 'Spider-Man 2', 'Ghost of Tsushima',
    'Death Stranding', 'Control', 'Alan Wake 2', 'Resident Evil 4 Remake', 'Resident Evil Village',
    'Resident Evil 2 Remake', 'Dead Space Remake', 'Lies of P', 'Lords of the Fallen', 'Armored Core VI',
    'Sekiro: Shadows Die Twice', 'Dark Souls III', 'Dark Souls Remastered', 'Bloodborne', 'Demon\'s Souls',
    'Nioh 2', 'Wo Long: Fallen Dynasty', 'Street Fighter 6', 'Tekken 8', 'Mortal Kombat 1',
    'Guilty Gear Strive', 'Hades II', 'Hades', 'Dead Cells', 'Hollow Knight',
    'Silksong', 'Celeste', 'Stardew Valley', 'Terraria', 'Valheim',
    'No Man\'s Sky', 'Satisfactory', 'Factorio', 'Dyson Sphere Program', 'Cities: Skies II',
    'Civilization VI', 'Civilization VII', 'Total War: Warhammer III', 'Crusader Kings III', 'Europa Universalis IV',
    'Hearts of Iron IV', 'Age of Empires IV', 'StarCraft II', 'Age of Empires II: DE', 'Command & Conquer Remastered',
    'Company of Heroes 3', 'Squad', 'Hell Let Loose', 'Arma 3', 'Arma Reforger',
    'DayZ', 'Escape from Tarkov', 'The Cycle: Frontier', ' Hunt: Showdown', 'Deep Rock Galactic',
    'Payday 3', 'Borderlands 3', 'Tiny Tina\'s Wonderlands', 'Destiny 2', 'Warframe',
    'Outriders', 'Remnant 2', 'Remnant: From the Ashes', 'Returnal', 'Ratchet & Clank: Rift Apart',
    'Uncharted: Legacy of Thieves', 'The Last of Us Part I', 'Days Gone', 'Metro Exodus', 'STALKER 2',
    'Atomic Heart', 'Atomic Heart', 'Biomutant', 'Scorn', 'Immortals of Aveum',
    'Forspoken', 'Forspoken', 'Avowed', 'Kingdom Come: Deliverance II', 'Mount & Blade II: Bannerlord',
    'Baldur\'s Gate: Enhanced Edition', 'Pillars of Eternity II', 'Divinity: Original Sin 2', 'Solasta', 'Baldur\'s Gate 3',
    'Persona 5 Royal', 'Persona 3 Reload', 'Yakuza: Like a Dragon', 'Like a Dragon: Infinite Wealth', 'Metaphor: ReFantazio',
    'Tales of Arise', 'Octopath Traveler II', 'Triangle Strategy', 'Fire Emblem Engage', 'Xenoblade Chronicles 3',
    'Zelda: Tears of the Kingdom', 'Zelda: Breath of the Wild', 'Super Mario Odyssey', 'Mario Kart 8 Deluxe', 'Smash Ultimate',
    'Animal Crossing', 'Splatoon 3', 'Bayonetta 3', 'Astral Chain', 'Kirby and the Forgotten Land',
    'Halo Infinite', 'Gears 5', 'Sea of Thieves', 'State of Decay 2', 'Grounded',
    'Palworld', 'Enshrouded', 'Soulmask', 'Bellwright', 'Nightingale',
    'Skull and Bones', 'Suicide Squad: Kill the Justice League', 'Gotham Knights', 'Marvel\'s Midnight Suns', 'Marvel\'s Spider-Man',
    'Marvel Rivals', 'Deadpool', 'Lego Star Wars: The Skywalker Saga', 'It Takes Two', 'A Way Out',
    'Split Fiction', 'Brothers: A Tale of Two Sons Remake', 'Portal 2', 'Half-Life: Alyx', 'Left 4 Dead 2',
    'Back 4 Blood', 'World War Z', 'Killing Floor 2', 'V Rising', 'Core Keeper',
    'Core Keeper', 'Core Keeper', 'Core Keeper', 'Core Keeper', 'Core Keeper',
];

// Expand to 300 with numbered esports / indie / classic entries
$extraPrefixes = ['Pro', 'Classic', 'Remastered', 'Definitive', 'Ultimate'];
$extraBases = [
    'Counter-Strike', 'Doom', 'Quake', 'Unreal Tournament', 'Titanfall',
    'MechWarrior', 'Falcon', 'IL-2', 'Silent Hunter', 'X4 Foundations',
    'Kerbal Space Program', 'Planet Zoo', 'Planet Coaster', 'Two Point Hospital', 'RimWorld',
    'Oxygen Not Included', 'Don\'t Starve Together', 'Project Zomboid', '7 Days to Die', 'The Forest',
    'Sons of The Forest', 'Green Hell', 'Subnautica', 'Subnautica: Below Zero', 'Outer Wilds',
    'Disco Elysium', 'Disco Elysium', 'Baldur\'s Gate', 'Icewind Dale', 'Planescape Torment',
    'Fallout 4', 'Fallout: New Vegas', 'Skyrim', 'Oblivion', 'Morrowind',
    'Mafia: Definitive', 'Mafia II', 'Mafia III', 'Sleeping Dogs', 'Yakuza 0',
    'Injustice 2', 'Injustice 2', 'Mortal Kombat 11', 'Injustice 2', 'MultiVersus',
    'Brawlhalla', 'Fall Guys', 'Rocket League', 'Trackmania', 'iRacing',
    'Automobilista 2', 'rFactor 2', 'Project CARS 3', 'WRC Generations', 'DiRT Rally 2.0',
    'Wreckfest', 'BeamNG.drive', 'SnowRunner', 'MudRunner', 'Farming Simulator 22',
    'Farming Simulator 25', 'Car Mechanic Simulator 2021', 'House Flipper 2', 'PowerWash Simulator', 'PC Building Simulator',
    'The Sims 4', 'SimCity', 'Cities: Skylines', 'Transport Fever 2', 'Railway Empire 2',
    'Anno 1800', 'Anno 117', 'Tropico 6', 'Surviving Mars', 'Frostpunk 2',
    'Frostpunk', 'This War of Mine', 'Papers Please', 'Beholder', 'Spiritfarer',
    'Gris', 'Journey', 'Abzû', 'Flower', 'The Witness',
    'Baba Is You', 'Return of the Obra Dinn', 'Outer Wilds', 'Her Story', 'What Remains of Edith Finch',
    'Firewatch', 'Gone Home', 'Life is Strange', 'Life is Strange 2', 'Tell Me Why',
    'Detroit: Become Human', 'Heavy Rain', 'Beyond: Two Souls', 'Until Dawn', 'The Quarry',
    'Little Nightmares III', 'Little Nightmares II', 'Inside', 'Limbo', 'Little Nightmares',
    'Amnesia: The Bunker', 'Amnesia: Rebirth', 'Outlast Trials', 'Phasmophobia', 'Devour',
    'Lethal Company', 'Content Warning', 'Buckshot Roulette', 'Balatro', 'Slay the Spire',
    'Monster Train 2', 'Inscryption', 'Loop Hero', 'Vampire Survivors', 'Brotato',
    'Risk of Rain 2', 'Gunfire Reborn', 'Deep Rock Galactic', 'GTFO', 'R.E.P.O.',
    'Lethal Company', 'Minecraft Dungeons', 'Diablo II: Resurrected', 'Diablo III', 'Grim Dawn',
    'Torchlight II', 'Last Epoch', 'Wolcen', 'Chronicon', 'Heroes of Hammerwatch 2',
];

while (count($titles) < 320) {
    $base = $extraBases[count($titles) % count($extraBases)];
    $suffix = ' #' . (count($titles) + 1);
    $titles[] = $base . $suffix;
}

$titles = array_slice(array_values(array_unique($titles)), 0, 300);

$tiers = ['low', 'low', 'mid', 'mid', 'high', 'high', 'ultra'];
$games = [];
foreach ($titles as $i => $name) {
    $tier = $tiers[$i % count($tiers)];
    $vram = match ($tier) {
        'low' => 2,
        'mid' => 4,
        'high' => 8,
        default => 12,
    };
    $games[] = [
        'id' => 'g' . ($i + 1),
        'slug' => preg_replace('/[^a-z0-9]+/', '-', strtolower($name)),
        'name' => $name,
        'name_fa' => $name,
        'tier' => $tier,
        'min_vram_gb' => $vram,
        'cpu_demand' => $tier === 'ultra' ? 90 : ($tier === 'high' ? 75 : ($tier === 'mid' ? 55 : 35)),
        'gpu_demand' => $tier === 'ultra' ? 95 : ($tier === 'high' ? 80 : ($tier === 'mid' ? 60 : 40)),
        'tags' => [$tier, $i % 3 === 0 ? 'multiplayer' : 'singleplayer'],
    ];
}

$out = dirname(__DIR__) . '/config/diagnostic_games.json';
file_put_contents($out, json_encode(['version' => 1, 'count' => count($games), 'games' => $games], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
echo "Wrote " . count($games) . " games to $out\n";
