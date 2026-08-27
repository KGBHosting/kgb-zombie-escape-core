/*
 * KGB Zombie Escape Core
 * Copyright (C) 2026 KGB Hosting
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * This first release candidate intentionally uses only stock Counter-Strike
 * assets. Zombie Escape maps and FastDL content are separate operator-owned
 * prerequisites and are not distributed by this plugin.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <fun>
#include <hamsandwich>

#define PLUGIN_NAME "KGB Zombie Escape Core"
#define PLUGIN_VERSION "0.1.0"
#define PLUGIN_AUTHOR "KGB Hosting"

#define TASK_BEGIN_INFECTION 71200
#define TASK_RESPAWN_BASE 71300

new g_max_players
new bool:g_round_active
new bool:g_infection_started
new bool:g_is_zombie[33]

new g_cvar_enabled
new g_cvar_min_players
new g_cvar_infection_delay
new g_cvar_zombie_ratio
new g_cvar_zombie_health
new g_cvar_zombie_speed
new g_cvar_zombie_gravity
new g_cvar_human_health
new g_cvar_human_armor
new g_cvar_respawn_delay
new g_cvar_display_name
new g_cvar_chat_prefix
new g_cvar_round_infinite

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)

    g_cvar_enabled = register_cvar("kgb_ze_enabled", "1")
    g_cvar_min_players = register_cvar("kgb_ze_min_players", "2")
    g_cvar_infection_delay = register_cvar("kgb_ze_infection_delay", "15.0")
    g_cvar_zombie_ratio = register_cvar("kgb_ze_zombie_ratio", "0.20")
    g_cvar_zombie_health = register_cvar("kgb_ze_zombie_health", "5000")
    g_cvar_zombie_speed = register_cvar("kgb_ze_zombie_speed", "310.0")
    g_cvar_zombie_gravity = register_cvar("kgb_ze_zombie_gravity", "0.80")
    g_cvar_human_health = register_cvar("kgb_ze_human_health", "100")
    g_cvar_human_armor = register_cvar("kgb_ze_human_armor", "50")
    g_cvar_respawn_delay = register_cvar("kgb_ze_respawn_delay", "3.0")
    g_cvar_display_name = register_cvar("kgb_ze_display_name", "KGB Zombie Escape")
    g_cvar_chat_prefix = register_cvar("kgb_ze_chat_prefix", "[KGB ZE]")

    register_event("HLTV", "on_new_round", "a", "1=0", "2=0")
    register_event("CurWeapon", "on_current_weapon", "be", "1=1")
    register_logevent("on_round_end", 2, "1=Round_End")

    RegisterHam(Ham_Spawn, "player", "on_player_spawn_post", 1)
    RegisterHam(Ham_TakeDamage, "player", "on_take_damage_pre", 0)
    RegisterHam(Ham_Killed, "player", "on_player_killed_post", 1)
    register_forward(FM_PlayerPreThink, "on_player_prethink")

    register_clcmd("say /ze", "command_player_status")
    register_clcmd("say_team /ze", "command_player_status")
    register_concmd("amx_ze_status", "command_admin_status", ADMIN_CFG)
    register_concmd("amx_ze_infect", "command_admin_infect", ADMIN_CFG, "<name or #userid>")

    g_max_players = get_maxplayers()
}

public plugin_cfg()
{
    server_cmd("exec addons/amxmodx/configs/kgb_zombie_escape.cfg")
    server_exec()

    g_cvar_round_infinite = get_cvar_pointer("mp_round_infinite")
    if (!g_cvar_round_infinite)
    {
        set_fail_state("KGB Zombie Escape requires ReGameDLL_CS and its mp_round_infinite CVar.")
        return
    }

    new round_infinite[32]
    get_pcvar_string(g_cvar_round_infinite, round_infinite, charsmax(round_infinite))
    if (contain(round_infinite, "b") == -1 || contain(round_infinite, "f") == -1)
    {
        set_fail_state("KGB Zombie Escape requires mp_round_infinite to include flags b and f.")
    }
}

public client_disconnect(id)
{
    remove_task(TASK_RESPAWN_BASE + id)
    g_is_zombie[id] = false
    check_remaining_humans()
}

public on_new_round()
{
    remove_task(TASK_BEGIN_INFECTION)
    g_round_active = false
    g_infection_started = false

    for (new id = 1; id <= g_max_players; id++)
    {
        remove_task(TASK_RESPAWN_BASE + id)
        g_is_zombie[id] = false
    }

    if (get_pcvar_num(g_cvar_enabled))
    {
        set_task(1.0, "prepare_round")
    }
}

public prepare_round()
{
    if (!get_pcvar_num(g_cvar_enabled))
    {
        return
    }

    new players[32], player_count
    get_players(players, player_count, "ah")

    if (player_count < get_pcvar_num(g_cvar_min_players))
    {
        announce("Waiting for at least %d players before infection begins.", get_pcvar_num(g_cvar_min_players))
        return
    }

    g_round_active = true

    for (new index = 0; index < player_count; index++)
    {
        make_human(players[index])
    }

    new Float:delay = get_pcvar_float(g_cvar_infection_delay)
    if (delay < 1.0)
    {
        delay = 1.0
    }

    announce("Initial infection begins in %.0f seconds. Humans: move toward the escape route.", delay)
    set_task(delay, "begin_infection", TASK_BEGIN_INFECTION)
}

public begin_infection()
{
    if (!g_round_active || g_infection_started || !get_pcvar_num(g_cvar_enabled))
    {
        return
    }

    new players[32], player_count
    get_players(players, player_count, "ah")

    if (player_count < get_pcvar_num(g_cvar_min_players))
    {
        g_round_active = false
        return
    }

    new Float:ratio = get_pcvar_float(g_cvar_zombie_ratio)
    if (ratio < 0.05)
    {
        ratio = 0.05
    }
    else if (ratio > 0.90)
    {
        ratio = 0.90
    }

    new zombie_count = floatround(float(player_count) * ratio, floatround_ceil)
    if (zombie_count < 1)
    {
        zombie_count = 1
    }
    if (zombie_count >= player_count)
    {
        zombie_count = player_count - 1
    }

    for (new index = player_count - 1; index > 0; index--)
    {
        new swap_index = random_num(0, index)
        new swap_value = players[index]
        players[index] = players[swap_index]
        players[swap_index] = swap_value
    }

    g_infection_started = true
    for (new index = 0; index < zombie_count; index++)
    {
        make_zombie(players[index], 0)
    }

    announce("Infection started with %d zombie%s. Reach the map escape objective.", zombie_count, zombie_count == 1 ? "" : "s")
}

public on_round_end()
{
    remove_task(TASK_BEGIN_INFECTION)
    g_round_active = false
    g_infection_started = false
}

public on_player_spawn_post(id)
{
    if (!is_user_alive(id) || !get_pcvar_num(g_cvar_enabled))
    {
        return HAM_IGNORED
    }

    if (g_round_active && g_infection_started)
    {
        make_zombie(id, 0)
    }
    else
    {
        make_human(id)
    }

    return HAM_IGNORED
}

public on_take_damage_pre(victim, inflictor, attacker, Float:damage, damage_bits)
{
    if (!g_round_active || !g_infection_started || !get_pcvar_num(g_cvar_enabled))
    {
        return HAM_IGNORED
    }

    if (attacker < 1 || attacker > g_max_players || attacker == victim)
    {
        return HAM_IGNORED
    }

    if (!is_user_alive(attacker) || !is_user_alive(victim) || !g_is_zombie[attacker] || g_is_zombie[victim])
    {
        return HAM_IGNORED
    }

    if (get_user_weapon(attacker) != CSW_KNIFE)
    {
        return HAM_IGNORED
    }

    make_zombie(victim, attacker)
    SetHamParamFloat(4, 0.0)

    return HAM_SUPERCEDE
}

public on_player_killed_post(victim, attacker, should_gib)
{
    if (!g_round_active || !g_infection_started || !get_pcvar_num(g_cvar_enabled))
    {
        return HAM_IGNORED
    }

    g_is_zombie[victim] = true

    new Float:delay = get_pcvar_float(g_cvar_respawn_delay)
    if (delay < 0.5)
    {
        delay = 0.5
    }

    remove_task(TASK_RESPAWN_BASE + victim)
    set_task(delay, "respawn_as_zombie", TASK_RESPAWN_BASE + victim)

    return HAM_IGNORED
}

public respawn_as_zombie(task_id)
{
    new id = task_id - TASK_RESPAWN_BASE

    if (!g_round_active || !g_infection_started || !is_user_connected(id) || is_user_alive(id))
    {
        return
    }

    g_is_zombie[id] = true
    cs_set_user_team(id, CS_TEAM_T)
    ExecuteHamB(Ham_CS_RoundRespawn, id)
}

public on_current_weapon(id)
{
    if (!is_user_alive(id) || !g_is_zombie[id])
    {
        return
    }

    if (read_data(2) != CSW_KNIFE)
    {
        strip_user_weapons(id)
        give_item(id, "weapon_knife")
    }
}

public on_player_prethink(id)
{
    if (!is_user_alive(id) || !g_is_zombie[id])
    {
        return FMRES_IGNORED
    }

    new Float:speed = get_pcvar_float(g_cvar_zombie_speed)
    if (speed > 0.0)
    {
        set_pev(id, pev_maxspeed, speed)
    }

    return FMRES_IGNORED
}

public command_player_status(id)
{
    if (!is_user_connected(id))
    {
        return PLUGIN_HANDLED
    }

    new humans, zombies
    count_roles(humans, zombies)

    new prefix[48], display_name[64]
    get_pcvar_string(g_cvar_chat_prefix, prefix, charsmax(prefix))
    get_pcvar_string(g_cvar_display_name, display_name, charsmax(display_name))

    client_print(id, print_chat, "%s %s: humans=%d zombies=%d infection=%s", prefix, display_name, humans, zombies, g_infection_started ? "active" : "waiting")

    return PLUGIN_HANDLED
}

public command_admin_status(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED
    }

    new humans, zombies
    count_roles(humans, zombies)
    console_print(id, "[KGB ZE] enabled=%d round_active=%d infection_started=%d humans=%d zombies=%d", get_pcvar_num(g_cvar_enabled), g_round_active, g_infection_started, humans, zombies)

    return PLUGIN_HANDLED
}

public command_admin_infect(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
    {
        return PLUGIN_HANDLED
    }

    new argument[32]
    read_argv(1, argument, charsmax(argument))

    new target = cmd_target(id, argument, CMDTARGET_ALLOW_SELF)
    if (!target || !is_user_alive(target))
    {
        return PLUGIN_HANDLED
    }

    remove_task(TASK_BEGIN_INFECTION)
    g_round_active = true
    g_infection_started = true
    make_zombie(target, id)

    return PLUGIN_HANDLED
}

stock make_human(id)
{
    if (!is_user_alive(id))
    {
        return
    }

    g_is_zombie[id] = false
    cs_set_user_team(id, CS_TEAM_CT)
    cs_reset_user_model(id)
    strip_user_weapons(id)
    give_item(id, "weapon_knife")
    give_item(id, "weapon_mp5navy")
    give_item(id, "weapon_usp")
    cs_set_user_bpammo(id, CSW_MP5NAVY, 120)
    cs_set_user_bpammo(id, CSW_USP, 100)
    set_user_health(id, get_pcvar_num(g_cvar_human_health))
    set_user_armor(id, get_pcvar_num(g_cvar_human_armor))
    set_user_gravity(id, 1.0)
    set_user_rendering(id)
}

stock make_zombie(id, infector)
{
    if (!is_user_alive(id))
    {
        return
    }

    g_is_zombie[id] = true
    cs_set_user_team(id, CS_TEAM_T)
    cs_reset_user_model(id)
    strip_user_weapons(id)
    give_item(id, "weapon_knife")
    set_user_health(id, get_pcvar_num(g_cvar_zombie_health))
    set_user_armor(id, 0)
    set_user_gravity(id, get_pcvar_float(g_cvar_zombie_gravity))
    set_user_rendering(id, kRenderFxGlowShell, 80, 180, 80, kRenderNormal, 8)

    if (infector > 0 && infector <= g_max_players && is_user_connected(infector))
    {
        new prefix[48], zombie_name[32], infector_name[32]
        get_pcvar_string(g_cvar_chat_prefix, prefix, charsmax(prefix))
        get_user_name(id, zombie_name, charsmax(zombie_name))
        get_user_name(infector, infector_name, charsmax(infector_name))
        client_print(0, print_chat, "%s %s infected %s.", prefix, infector_name, zombie_name)
    }

    check_remaining_humans()
}

stock check_remaining_humans()
{
    if (!g_round_active || !g_infection_started)
    {
        return
    }

    new humans, zombies
    count_roles(humans, zombies)

    if (humans == 0 && zombies > 0)
    {
        announce("All humans were infected. Zombies win the round.")
    }
}

stock count_roles(&humans, &zombies)
{
    humans = 0
    zombies = 0

    for (new id = 1; id <= g_max_players; id++)
    {
        if (!is_user_connected(id) || !is_user_alive(id))
        {
            continue
        }

        if (g_is_zombie[id])
        {
            zombies++
        }
        else
        {
            humans++
        }
    }
}

stock announce(const format[], any:...)
{
    new message[190], prefix[48]
    vformat(message, charsmax(message), format, 2)
    get_pcvar_string(g_cvar_chat_prefix, prefix, charsmax(prefix))
    client_print(0, print_chat, "%s %s", prefix, message)
}
