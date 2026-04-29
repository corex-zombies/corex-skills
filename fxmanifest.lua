fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'corex-skills'
description 'COREX Skill Tree — Combat / Survivor / Craftsman with real gameplay modifiers'
author 'ABUGIZA'
version '1.1.0'

shared_scripts {
    'config.lua',
    'shared/skills.lua',
    'shared/modifiers.lua'
}

server_scripts {
    'server/main.lua',
    'server/xp.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/assets/tree-bg.png'
}

server_exports {
    'HasSkill',
    'GetUnlockedSkills',
    'GetSkillPoints',
    'AddSkillPoints',
    'GiveSkillPoints',
    'AwardXp',
    'GetXp',
    'GetXpTotal',
    'GetModifiers',
    'GetModifier',
    'CanCraftRecipe',
    'GetSkillInfo',
    'GetSkillForFlag'
}

exports {
    'HasSkill',
    'GetLocalModifiers',
    'GetLocalModifier',
    'GetLocalUnlocked',
    'OpenLockpick'
}

dependencies { 'corex-core' }
