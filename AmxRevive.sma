#include <AmxModX>
#include <ReApi>
#include <FakeMeta>

#define StartedRevive(%1) (set_entvar(%1, var_iuser1, 1))
#define StopedRevive(%1) (set_entvar(%1, var_iuser1, 0))
#define IsReviving(%1) (get_entvar(%1, var_iuser1) == 1)
#define IsValidTeam(%1) (TEAM_TERRORIST <= get_member(%1, m_iTeam) <= TEAM_CT)

enum any:iData {
	Corpse,
	ReviveIndex,
	Float:flSpawnDelay,
	Float:flDelay,
	CountRevive
};

enum _:Cvars {
	PROGRESS_BAR,
	DURATION,
	Float:DISTANCE,
	Float:DELAY,
	Float:FLOOD,
	COUNT,
	ONE_VS_ONE,
	Float:HEALTH
};

new const BODY_CLASSNAME[] = "player_corpse";

new g_pPlayerData[33][iData],
	g_pCvars[Cvars];

public client_disconnected(pId) {
	CorpseRemove(pId);
}

public plugin_init() {
	register_plugin(
		.plugin_name = "[AMXX] Revive",
		.version = "0.1",
		.author = "@jbengine"
	);

	register_dictionary(.filename = "AmxRevive.txt");

	BindCvars();
	ForwardAndMessage();
}

public BindCvars() {
	bind_pcvar_num(create_cvar(
		.name = "amx_revive_status_bar",
		.string = "1.0",
		.description = "Включить полоску прогресса? 0 - Нет, 1 - Да.",
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 1.0
	), g_pCvars[PROGRESS_BAR]);

	bind_pcvar_num(create_cvar(
		.name = "amx_revive_duration_time",
		.string = "5.0",
		.description = "Длительность процесса возрождения.",
		.has_min = true,
		.min_val = 1.0
	), g_pCvars[DURATION]);

	bind_pcvar_float(create_cvar(
		.name = "amx_revive_distance",
		.string = "50.0",
		.description = "Максимальная дальность для возрождения.",
		.has_min = true,
		.min_val = 50.0
	), g_pCvars[DISTANCE]);

	bind_pcvar_float(create_cvar(
		.name = "amx_revive_delay",
		.string = "2.0",
		.description = "Через сколько можно возродить игрока?",
		.has_min = true,
		.min_val = 1.0
	), g_pCvars[DELAY]);

	bind_pcvar_float(create_cvar(
		.name = "amx_revive_flood",
		.string = "2.0",
		.description = "Через сколько можно использовать снова? (Защита от спама)",
		.has_min = true,
		.min_val = 1.0
	), g_pCvars[FLOOD]);

	bind_pcvar_num(create_cvar(
		.name = "amx_revive_count",
		.string = "5.0",
		.description = "Максимальное кол-во возрождений в раунд? 0 - Бесконечно.",
		.has_min = true,
		.min_val = 1.0
	), g_pCvars[COUNT]);

	bind_pcvar_num(create_cvar(
		.name = "amx_revive_one_vs_one",
		.string = "1.0",
		.description = "Нельзя возрождать, когда остались 1 на 1? 0 - Можно, 1 - Нельзя.",
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 1.0
	), g_pCvars[ONE_VS_ONE]);

	bind_pcvar_float(create_cvar(
		.name = "amx_revive_health",
		.string = "100.0",
		.description = "Сколько установить здоровья тому, кого возродили?",
		.has_min = true,
		.min_val = 1.0
	), g_pCvars[HEALTH]);

	AutoExecConfig(.autoCreate = true, .name = "AmxRevive", .folder = "cs-gsrc");
}

public ForwardAndMessage() {
	register_forward(FM_CmdStart, "fw_CmdStart");
	register_message(get_user_msgid("ClCorpse"), "MsgHookClCorpse");
	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", .post = true);
	RegisterHookChain(RG_CSGameRules_RestartRound, "RG_CSGameRules_RestartRound_Pre", .post = false);
}

public fw_CmdStart(pId, uc_handle) {
	if(!is_user_alive(pId))
		return;

	new Float:gametime = get_gametime();

	if(g_pPlayerData[pId][flDelay] > gametime)
		return;		

	if (g_pCvars[ONE_VS_ONE] && rg_is_1v1())
		return;

	if(get_uc(uc_handle, UC_Buttons) & IN_USE && ~get_entvar(pId, var_oldbuttons) & IN_USE && !g_pPlayerData[pId][ReviveIndex])
		GoRevive(pId);
	else if(get_entvar(pId, var_oldbuttons) & IN_USE && ~get_uc(uc_handle, UC_Buttons) & IN_USE && g_pPlayerData[pId][ReviveIndex])
		StopRevive(pId);
}

public CBasePlayer_Spawn_Post(pId) {
	CorpseRemove(pId);
	
	arrayset(g_pPlayerData[pId], 0, iData);
}

public GoRevive(pId) {
	if(g_pPlayerData[pId][ReviveIndex])
	StopRevive(pId);

	new pArray[MAX_PLAYERS], pNum;
	
	get_players(pArray, pNum, "be", get_member(pId, m_iTeam) == TEAM_CT ? "CT" : "TERRORIST");
	
	if (!pArray[0] || !pNum)
		return;
	
	new Float:flPlayerOrigin[3]; get_entvar(pId, var_origin, flPlayerOrigin);

	for (new i, pPlayer, pEnt, Float:flEntityOrigin[3]; i < pNum; i++) {
		pPlayer = pArray[i];
		
		pEnt = g_pPlayerData[pPlayer][Corpse];
		
		if(is_nullent(pEnt))
			continue;
		
		if(IsReviving(pEnt))
			continue;

		get_entvar(pEnt, var_origin, flEntityOrigin);
		
		if(vector_distance(flPlayerOrigin, flEntityOrigin) > g_pCvars[DISTANCE])
			continue;

		if(g_pCvars[DELAY]) 
			if(g_pPlayerData[pPlayer][flSpawnDelay] > get_gametime())
				continue;

		if(g_pCvars[COUNT] > 0)
			if(g_pPlayerData[pId][CountRevive] >= g_pCvars[COUNT]) {
				client_print_color(pId, print_team_default, "%l %l", "RT_PREFIX", "RT_LIMIT", g_pCvars[COUNT]);
				return;
			}

		if(g_pPlayerData[pId][ReviveIndex])
			StopRevive(pId);

		StartedRevive(pEnt);

		g_pPlayerData[pId][ReviveIndex] = pEnt;

		if(g_pCvars[PROGRESS_BAR])
			rg_send_bartime(pId, g_pCvars[DURATION], bool:(g_pCvars[PROGRESS_BAR] == 1));

		set_task(float(g_pCvars[DURATION]), "RespawnFriend", pId);

		RequestFrame("CBasePlayer_PreThink", pId);
	}
}

public RG_CSGameRules_RestartRound_Pre() {
	for(new pId; pId <= MaxClients; pId++) {
		if(g_pCvars[COUNT] > 0)
			if(g_pPlayerData[pId][CountRevive] > 0) 
				g_pPlayerData[pId][CountRevive] = 0;
	}
}

public RespawnFriend(pId) {
	new ent = g_pPlayerData[pId][ReviveIndex];
	
	if(is_nullent(ent))
		return;

	StopRevive(pId);

	if(g_pCvars[COUNT] > 0) {
		g_pPlayerData[pId][CountRevive]++;
		client_print_color(pId, print_team_default, "%l %l", "RT_PREFIX", "RT_COUNT_PLUS", g_pCvars[COUNT] - g_pPlayerData[pId][CountRevive]);
	}

	new pPlayer = get_entvar(ent, var_owner);

	if(g_pCvars[ONE_VS_ONE] && rg_is_1v1())
		return;

	rg_round_respawn(pPlayer);
	set_entvar(pPlayer, var_health, Float:g_pCvars[HEALTH]);

	client_print_color(0, print_team_default, "%l %l", "RT_PREFIX", "RT_REVIVED", pId, pPlayer);

	g_pPlayerData[pPlayer][flSpawnDelay] = get_gametime() + g_pCvars[DELAY];
}

public StopRevive(pId) {
	if (!g_pPlayerData[pId][ReviveIndex])
		return;
	
	new ent = g_pPlayerData[pId][ReviveIndex];
	
	StopedRevive(ent);
	
	g_pPlayerData[pId][ReviveIndex] = 0;
	g_pPlayerData[pId][flDelay] = get_gametime() + g_pCvars[FLOOD];
	
	if(g_pCvars[PROGRESS_BAR])
		rg_send_bartime(pId, 0);
	
	if(task_exists(pId)) 
		remove_task(pId);
}

public CBasePlayer_PreThink(pId) {
	if (!is_user_alive(pId))
		StopRevive(pId);
	else
	{
		if(!g_pPlayerData[pId][ReviveIndex])
			return;
		
		new Float:origin[3], Float:origin2[3];
		get_entvar(pId, var_origin, origin);
		get_entvar(g_pPlayerData[pId][ReviveIndex], var_origin, origin2);
		
		if(vector_distance(origin, origin2) > g_pCvars[DISTANCE]) {
			StopRevive(pId);
			client_print_color(pId, print_team_default, "%l %l", "RT_PREFIX", "RT_DISTANCE_FAIL");
		}
		else
			RequestFrame("CBasePlayer_PreThink", pId);
	}
}

public MsgHookClCorpse() {
	new ent = rg_create_entity("info_target");
	
	if (is_nullent(ent))
		return PLUGIN_CONTINUE;
	
	new player = get_msg_arg_int(12);
	
	if (!IsValidTeam(player))
		return PLUGIN_CONTINUE;
	
	g_pPlayerData[player][Corpse] = ent;
	
	new Float:origin[3], Float:angles[3];
	
	get_entvar(player, var_origin, origin);
	get_entvar(player, var_angles, angles);

	new model[32]; get_msg_arg_string(1, model, charsmax(model));
	
	engfunc(EngFunc_SetModel, ent, fmt("models/player/%s/%s.mdl", model, model));
	engfunc(EngFunc_SetSize, ent, Float:{ -24.0, -24.0, 0.0 }, Float:{ 24.0, 24.0, 24.0 });
	engfunc(EngFunc_SetOrigin, ent, origin);
	
	set_entvar(ent, var_classname, BODY_CLASSNAME);
	set_entvar(ent, var_angles, angles);
	set_entvar(ent, var_body, get_msg_arg_int(10));
	set_entvar(ent, var_framerate, 1.0);
	set_entvar(ent, var_animtime, 0.0);
	set_entvar(ent, var_sequence, get_msg_arg_int(9));
	set_entvar(ent, var_owner, player);
	set_entvar(ent, var_team, get_msg_arg_int(11));
	
	StopedRevive(ent);
	
	return PLUGIN_HANDLED;
}

public CorpseRemove(pId) {
	new corpse = g_pPlayerData[pId][Corpse];
	
	if(!is_nullent(corpse)) 
        set_entvar(corpse, var_flags, FL_KILLME);
	
	g_pPlayerData[pId][Corpse] = 0;
}

stock bool:rg_is_1v1() {
	new alive_t, alive_ct; rg_initialize_player_counts(alive_t, alive_ct);
	
	return bool:(alive_t == 1 && alive_ct == 1);
}