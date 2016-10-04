/*
 * Admin Bomb Plugin.
 * by: shanapu
 * https://github.com/shanapu/AdminBomb
 *
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */


/******************************************************************************
                   STARTUP
******************************************************************************/


//Includes
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <colors>
#include <autoexecconfig>
#include <emitsoundany>
#include <mystocks>


//Compiler Options
#pragma semicolon 1
#pragma newdecls required


//Console Variables
ConVar gc_bEnable;
ConVar gc_sCustomCommand;
ConVar gc_sSoundBoomPath;
ConVar gc_fBombRadius;


//Strings
char g_sSoundBoomPath[256];


//Integers
int g_ExplosionSprite;


//Info
public Plugin myinfo = {
	name = "Admin Bomb", 
	author = "shanapu", 
	description = "Admin command to blow up an player", 
	version = "1.0", 
	url = "https://github.com/shanapu/AdminBomb"
};


//Start
public void OnPluginStart()
{
	//Translation
	LoadTranslations("AdminBomb.phrases");
	
	
	//Admin commands
	RegAdminCmd("sm_bomb", AdminCommand_Bomb, ADMFLAG_GENERIC, "Admin command to blow up an player");
	
	
	//AutoExecConfig
	AutoExecConfig_SetFile("AdminBomb");
	AutoExecConfig_SetCreateFile(true);
	
	
	gc_bEnable = AutoExecConfig_CreateConVar("sm_adminbomb_enable", "1", "0 - disabled / 1 - enable AdminBomb plugin");
	gc_sCustomCommand = AutoExecConfig_CreateConVar("sm_adminbomb_cmds", "blowup,nuke", "Set your custom chat command for admin bomb(!bomb (no 'sm_'/'!')(seperate with comma ', ')(max. 12 commands))");
	gc_sSoundBoomPath = AutoExecConfig_CreateConVar("sm_suicidebomber_sounds_boom", "music/MyJailbreak/boom.mp3", "Path to the soundfile which should be played on detonation.");
	gc_fBombRadius = AutoExecConfig_CreateConVar("sm_suicidebomber_bomb_radius", "200.0", "0 - disable hurt nearby player / set the radius for bomb damage", _, true, 10.0, true, 999.0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	gc_sSoundBoomPath.GetString(g_sSoundBoomPath, sizeof(g_sSoundBoomPath));
}


//ConVarChange for Strings
public int OnSettingChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (convar == gc_sSoundBoomPath)
	{
		strcopy(g_sSoundBoomPath, sizeof(g_sSoundBoomPath), newValue);
		PrecacheSoundAnyDownload(g_sSoundBoomPath);
	}
}

public void OnConfigsExecuted()
{
	//Set custom Commands
	int iCount = 0;
	char sCommands[128], sCommandsL[12][32], sCommand[32];
	
	//Admin remove player from queue
	gc_sCustomCommand.GetString(sCommands, sizeof(sCommands));
	ReplaceString(sCommands, sizeof(sCommands), " ", "");
	iCount = ExplodeString(sCommands, ",", sCommandsL, sizeof(sCommandsL), sizeof(sCommandsL[]));
	
	for (int i = 0; i < iCount; i++)
	{
		Format(sCommand, sizeof(sCommand), "sm_%s", sCommandsL[i]);
		if (GetCommandFlags(sCommand) == INVALID_FCVAR_FLAGS)  //if command not already exist
			RegAdminCmd(sCommand, AdminCommand_Bomb, ADMFLAG_GENERIC, "Admin command to blow up an player");
	}
}


public void OnMapStart()
{
	PrecacheSoundAnyDownload(g_sSoundBoomPath);
	g_ExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

/******************************************************************************
                   COMMANDS
******************************************************************************/


public Action AdminCommand_Bomb(int client, int args)
{
	if (!IsValidClient(client, true, true))
		return Plugin_Handled;
	
	if (!gc_bEnable)
	{
		CReplyToCommand(client, "%t %t", "adminbomb_tag", "adminbomb_disabled");
		return Plugin_Handled;
	}
	
	if (args > 0)
	{
		Menu hMenu = CreateMenu(ViewQueueMenuHandle);
		
		char menuinfo[64];
		Format(menuinfo, sizeof(menuinfo), "t", "ratio_remove", client);
		SetMenuTitle(hMenu, menuinfo);
		
		for (int i = 1; i <= MaxClients; ++i)
		{
			char userid[11];
			char username[MAX_NAME_LENGTH];
			IntToString(GetClientUserId(i), userid, sizeof(userid));
			Format(username, sizeof(username), "%N", i);
			hMenu.AddItem(userid, username);
		}
		
		hMenu.ExitBackButton = true;
		hMenu.ExitButton = true;
		DisplayMenu(hMenu, client, 15);
	}
	else
	{
		char strTarget[32]; 
		GetCmdArg(1, strTarget, sizeof(strTarget));
		int iClient = StringToInt(strTarget);
		
		BlowUpClient(iClient);
	}
	
	
	
	return Plugin_Handled;
}


public int ViewQueueMenuHandle(Menu hMenu, MenuAction action, int client, int option)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		hMenu.GetItem(option, info, sizeof(info));
		int user = GetClientOfUserId(StringToInt(info)); 
		
		BlowUpClient(user);
		
		CPrintToChatAll("%t %t", "ratio_tag", "ratio_removed", client, user);
		
	}
	else if (action == MenuAction_End)
	{
		delete hMenu;
	}
}


/******************************************************************************
                   FUNCTION
******************************************************************************/

void BlowUpClient(int client)
{
	EmitSoundToAllAny(g_sSoundBoomPath);
	
	float suicide_bomber_vec[3];
	GetClientAbsOrigin(client, suicide_bomber_vec);
	
	TE_SetupExplosion(suicide_bomber_vec, g_ExplosionSprite, 10.0, 1, 0, RoundToFloor(gc_fBombRadius.FloatValue), 5000);
	TE_SendToAll();
	
	
	int iMaxClients = GetMaxClients();
	int deathList[MAXPLAYERS+1]; //store players that this bomb kills
	int numKilledPlayers = 0;
	
	if (gc_fBombRadius.FloatValue > 0) for (int i = 1; i <= iMaxClients; ++i)
	{
		//Check that client is a real player who is alive
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			float vec_nearby[3];
			GetClientAbsOrigin(i, vec_nearby);
			
			float distance = GetVectorDistance(vec_nearby, suicide_bomber_vec, false);
			
			//If CT was in explosion radius, damage or kill them
			//Formula used: damage = 200 - (d/2)
			int damage = RoundToFloor(gc_fBombRadius.FloatValue - (distance / 2.0));
			
			if (damage <= 0) //this player was not damaged 
			continue;
			
			//damage the surrounding players
			int curHP = GetClientHealth(i);
			if (curHP - damage <= 0) 
			{
				deathList[numKilledPlayers] = i;
				numKilledPlayers++;
			}
			else
			{ //Survivor
				SetEntityHealth(i, curHP - damage);
				IgniteEntity(i, 2.0);
			}
		}
	}
	if (numKilledPlayers > 0) 
	{
		for (int i = 0; i < numKilledPlayers; ++i)
		{
			ForcePlayerSuicide(deathList[i]);
		}
	}
	ForcePlayerSuicide(client);
}
