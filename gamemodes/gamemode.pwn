/*
	myGM v0.2
	* Please check versionHistory.txt for more details
	
#Authors: Maurice and Yamato
#Site: tutoriale-pe.net
#Like #Share #Subscribe

*/

/*
if(sscanf(params, "iii", model,color1,color2)) return SCM;;;
*/

#include 	<a_samp>
#include	<zcmd>
#include	<sscanf2>
#include	<foreach>
#include	<crashdetect>


#undef	  	MAX_PLAYERS
#define	 	MAX_PLAYERS			50

#include 	<a_mysql>

#define		MYSQL_HOST 			"127.0.0.1"
#define		MYSQL_USER 			"root"
#define		MYSQL_PASSWORD 		""
#define		MYSQL_DATABASE 		"sampdb"

#define		SECONDS_TO_LOGIN 	30

#define 	DEFAULT_POS_X 		1958.3783
#define 	DEFAULT_POS_Y 		1343.1572
#define 	DEFAULT_POS_Z 		15.3746
#define 	DEFAULT_POS_A 		270.1425

#define COLOR_ADMCHAT 0xFFC266AA
#define COLOR_GREY 0xC3C3C3AA
#define COLOR_LIGHTBLUE 0x33CCFFAA
#define COLOR_LIGHTRED 0xFF6347AA
#define COLOR_OOC 0xE0FFFFAA
#define COLOR_RED 0xAA3333AA
#define COLOR_YELLOW 0xFFFF00AA
#define COLOR_PENTRUTEST 0xFF0000AA

// MySQL connection handle
new MySQL: g_SQL;

// player data
enum E_PLAYERS
{
	ID,
	Name[MAX_PLAYER_NAME],
	Password[65], // the output of SHA256_PassHash function (which was added in 0.3.7 R1 version) is always 256 bytes in length, or the equivalent of 64 Pawn cells
	Salt[17],
	Kills,
	Deaths,
	Float: X_Pos,
	Float: Y_Pos,
	Float: Z_Pos,
	Float: A_Pos,
	Interior,
	HelperLevel,

	Cache: Cache_ID,
	bool: IsLoggedIn,
	LoginAttempts,
	LoginTimer
};
new PlayerData[MAX_PLAYERS][E_PLAYERS];

new HelperDuty[MAX_PLAYERS];
new HelperOcupat[MAX_PLAYERS];
new HelperAtribuit[MAX_PLAYERS];
new ConversatieOpen[MAX_PLAYERS];
new IntrebareStocata[MAX_PLAYERS][128];

new HelpMeTimer[MAX_PLAYERS];

new g_MysqlRaceCheck[MAX_PLAYERS];

// dialog data
enum
{
	DIALOG_UNUSED,

	DIALOG_LOGIN,
	DIALOG_REGISTER
};

main() {}


public OnGameModeInit()
{
	new MySQLOpt: option_id = mysql_init_options();

	mysql_set_option(option_id, AUTO_RECONNECT, true); // it automatically reconnects when loosing connection to mysql server

	g_SQL = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, option_id); // AUTO_RECONNECT is enabled for this connection handle only
	if (g_SQL == MYSQL_INVALID_HANDLE || mysql_errno(g_SQL) != 0)
	{
		print("MySQL connection failed. Server is shutting down.");
		SendRconCommand("exit"); // close the server if there is no connection
		return 1;
	}

	print("MySQL connection is successful.");
	
	// if the table has been created, the "SetupPlayerTable" function does not have any purpose so you may remove it completely
	SetupPlayerTable();
	return 1;
}

public OnGameModeExit()
{
	// save all player data before closing connection
	for (new i = 0, j = GetPlayerPoolSize(); i <= j; i++) // GetPlayerPoolSize function was added in 0.3.7 version and gets the highest playerid currently in use on the server
	{
		if (IsPlayerConnected(i))
		{
			// reason is set to 1 for normal 'Quit'
			OnPlayerDisconnect(i, 1);
		}
	}

	mysql_close(g_SQL);
	return 1;
}

public OnPlayerConnect(playerid)
{
	g_MysqlRaceCheck[playerid]++;

	// reset player data
	static const empty_player[E_PLAYERS];
	PlayerData[playerid] = empty_player;

	HelperDuty[playerid] = 0;
	HelperOcupat[playerid] = -1;
	HelperAtribuit[playerid] = -1;
	ConversatieOpen[playerid] = 0;
	IntrebareStocata[playerid] = "Ceva";
	
	HelpMeTimer[playerid] = 0;
	
	GetPlayerName(playerid, PlayerData[playerid][Name], MAX_PLAYER_NAME);

	// send a query to recieve all the stored player data from the table
	new query[103];
	mysql_format(g_SQL, query, sizeof query, "SELECT * FROM `players` WHERE `username` = '%e' LIMIT 1", PlayerData[playerid][Name]);
	mysql_tquery(g_SQL, query, "OnPlayerDataLoaded", "dd", playerid, g_MysqlRaceCheck[playerid]);
	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
	g_MysqlRaceCheck[playerid]++;

	UpdatePlayerData(playerid, reason);

	// if the player was kicked (either wrong password or taking too long) during the login part, remove the data from the memory
	if (cache_is_valid(PlayerData[playerid][Cache_ID]))
	{
		cache_delete(PlayerData[playerid][Cache_ID]);
		PlayerData[playerid][Cache_ID] = MYSQL_INVALID_CACHE;
	}

	// if the player was kicked before the time expires (30 seconds), kill the timer
	if (PlayerData[playerid][LoginTimer])
	{
		KillTimer(PlayerData[playerid][LoginTimer]);
		PlayerData[playerid][LoginTimer] = 0;
	}

	// sets "IsLoggedIn" to false when the player disconnects, it prevents from saving the player data twice when "gmx" is used
	PlayerData[playerid][IsLoggedIn] = false;
	
	if(HelpMeTimer[playerid])
	{
		KillTimer(HelpMeTimer[playerid]);
		HelpMeTimer[playerid] = 0;
	}
	
	return 1;
}

public OnPlayerSpawn(playerid)
{
	// spawn the player to their last saved position
	SetPlayerInterior(playerid, PlayerData[playerid][Interior]);
	SetPlayerPos(playerid, PlayerData[playerid][X_Pos], PlayerData[playerid][Y_Pos], PlayerData[playerid][Z_Pos]);
	SetPlayerFacingAngle(playerid, PlayerData[playerid][A_Pos]);
	
	SetCameraBehindPlayer(playerid);
	return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
	UpdatePlayerDeaths(playerid);
	UpdatePlayerKills(killerid);
	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch (dialogid)
	{
		case DIALOG_UNUSED: return 1; // Useful for dialogs that contain only information and we do nothing depending on whether they responded or not

		case DIALOG_LOGIN:
		{
			if (!response) return Kick(playerid);

			new hashed_pass[65];
			SHA256_PassHash(inputtext, PlayerData[playerid][Salt], hashed_pass, 65);

			if (strcmp(hashed_pass, PlayerData[playerid][Password]) == 0)
			{
				//correct password, spawn the player
				ShowPlayerDialog(playerid, DIALOG_UNUSED, DIALOG_STYLE_MSGBOX, "Login", "You have been successfully logged in.", "Okay", "");

				// sets the specified cache as the active cache so we can retrieve the rest player data
				cache_set_active(PlayerData[playerid][Cache_ID]);

				AssignPlayerData(playerid);

				// remove the active cache from memory and unsets the active cache as well
				cache_delete(PlayerData[playerid][Cache_ID]);
				PlayerData[playerid][Cache_ID] = MYSQL_INVALID_CACHE;

				KillTimer(PlayerData[playerid][LoginTimer]);
				PlayerData[playerid][LoginTimer] = 0;
				PlayerData[playerid][IsLoggedIn] = true;

				// spawn the player to their last saved position after login
				SetSpawnInfo(playerid, NO_TEAM, 0, PlayerData[playerid][X_Pos], PlayerData[playerid][Y_Pos], PlayerData[playerid][Z_Pos], PlayerData[playerid][A_Pos], 0, 0, 0, 0, 0, 0);
				SpawnPlayer(playerid);
			}
			else
			{
				PlayerData[playerid][LoginAttempts]++;

				if (PlayerData[playerid][LoginAttempts] >= 3)
				{
					ShowPlayerDialog(playerid, DIALOG_UNUSED, DIALOG_STYLE_MSGBOX, "Login", "You have mistyped your password too often (3 times).", "Okay", "");
					DelayedKick(playerid);
				}
				else ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Login", "Wrong password!\nPlease enter your password in the field below:", "Login", "Abort");
			}
		}
		case DIALOG_REGISTER:
		{
			if (!response) return Kick(playerid);

			if (strlen(inputtext) <= 5) return ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Registration", "Your password must be longer than 5 characters!\nPlease enter your password in the field below:", "Register", "Abort");

			// 16 random characters from 33 to 126 (in ASCII) for the salt
			for (new i = 0; i < 16; i++) PlayerData[playerid][Salt][i] = random(94) + 33;
			SHA256_PassHash(inputtext, PlayerData[playerid][Salt], PlayerData[playerid][Password], 65);

			new query[221];
			mysql_format(g_SQL, query, sizeof query, "INSERT INTO `players` (`username`, `password`, `salt`) VALUES ('%e', '%s', '%e')", PlayerData[playerid][Name], PlayerData[playerid][Password], PlayerData[playerid][Salt]);
			mysql_tquery(g_SQL, query, "OnPlayerRegister", "d", playerid);
		}

		default: return 0; // dialog ID was not found, search in other scripts
	}
	return 1;
}

//-----------------------------------------------------

forward OnPlayerDataLoaded(playerid, race_check);
public OnPlayerDataLoaded(playerid, race_check)
{
	/*	race condition check:
		player A connects -> SELECT query is fired -> this query takes very long
		while the query is still processing, player A with playerid 2 disconnects
		player B joins now with playerid 2 -> our laggy SELECT query is finally finished, but for the wrong player
		what do we do against it?
		we create a connection count for each playerid and increase it everytime the playerid connects or disconnects
		we also pass the current value of the connection count to our OnPlayerDataLoaded callback
		then we check if current connection count is the same as connection count we passed to the callback
		if yes, everything is okay, if not, we just kick the player
	*/
	if (race_check != g_MysqlRaceCheck[playerid]) return Kick(playerid);

	new string[115];
	if(cache_num_rows() > 0)
	{
		// we store the password and the salt so we can compare the password the player inputs
		// and save the rest so we won't have to execute another query later
		cache_get_value(0, "password", PlayerData[playerid][Password], 65);
		cache_get_value(0, "salt", PlayerData[playerid][Salt], 17);

		// saves the active cache in the memory and returns an cache-id to access it for later use
		PlayerData[playerid][Cache_ID] = cache_save();

		format(string, sizeof string, "This account (%s) is registered. Please login by entering your password in the field below:", PlayerData[playerid][Name]);
		ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Login", string, "Login", "Abort");

		// from now on, the player has 30 seconds to login
		PlayerData[playerid][LoginTimer] = SetTimerEx("OnLoginTimeout", SECONDS_TO_LOGIN * 1000, false, "d", playerid);
	}
	else
	{
		format(string, sizeof string, "Welcome %s, you can register by entering your password in the field below:", PlayerData[playerid][Name]);
		ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Registration", string, "Register", "Abort");
	}
	return 1;
}

forward OnLoginTimeout(playerid);
public OnLoginTimeout(playerid)
{
	// reset the variable that stores the timerid
	PlayerData[playerid][LoginTimer] = 0;
	
	ShowPlayerDialog(playerid, DIALOG_UNUSED, DIALOG_STYLE_MSGBOX, "Login", "You have been kicked for taking too long to login successfully to your account.", "Okay", "");
	DelayedKick(playerid);
	return 1;
}

forward OnPlayerRegister(playerid);
public OnPlayerRegister(playerid)
{
	// retrieves the ID generated for an AUTO_INCREMENT column by the sent query
	PlayerData[playerid][ID] = cache_insert_id();

	ShowPlayerDialog(playerid, DIALOG_UNUSED, DIALOG_STYLE_MSGBOX, "Registration", "Account successfully registered, you have been automatically logged in.", "Okay", "");

	PlayerData[playerid][IsLoggedIn] = true;

	PlayerData[playerid][X_Pos] = DEFAULT_POS_X;
	PlayerData[playerid][Y_Pos] = DEFAULT_POS_Y;
	PlayerData[playerid][Z_Pos] = DEFAULT_POS_Z;
	PlayerData[playerid][A_Pos] = DEFAULT_POS_A;
	
	SetSpawnInfo(playerid, NO_TEAM, 0, PlayerData[playerid][X_Pos], PlayerData[playerid][Y_Pos], PlayerData[playerid][Z_Pos], PlayerData[playerid][A_Pos], 0, 0, 0, 0, 0, 0);
	SpawnPlayer(playerid);
	return 1;
}

forward _KickPlayerDelayed(playerid);
public _KickPlayerDelayed(playerid)
{
	Kick(playerid);
	return 1;
}


//-----------------------------------------------------

AssignPlayerData(playerid)
{
	cache_get_value_int(0, "id", PlayerData[playerid][ID]);
	
	cache_get_value_int(0, "kills", PlayerData[playerid][Kills]);
	cache_get_value_int(0, "deaths", PlayerData[playerid][Deaths]);
	
	cache_get_value_float(0, "x", PlayerData[playerid][X_Pos]);
	cache_get_value_float(0, "y", PlayerData[playerid][Y_Pos]);
	cache_get_value_float(0, "z", PlayerData[playerid][Z_Pos]);
	cache_get_value_float(0, "angle", PlayerData[playerid][A_Pos]);
	cache_get_value_int(0, "interior", PlayerData[playerid][Interior]);
	
	cache_get_value_int(0, "HelperLevel", PlayerData[playerid][HelperLevel]);
	
	new string[128];
	format(string, sizeof(string), "%s (%d) are level helper %d", PlayerData[playerid][Name], playerid, PlayerData[playerid][HelperLevel]);
	printf(string);
	
	return 1;
}

DelayedKick(playerid, time = 500)
{
	SetTimerEx("_KickPlayerDelayed", time, false, "d", playerid);
	return 1;
}

SetupPlayerTable()
{
	mysql_tquery(g_SQL, "CREATE TABLE IF NOT EXISTS `players` (`id` int(11) NOT NULL AUTO_INCREMENT,`username` varchar(24) NOT NULL,`password` char(64) NOT NULL,`salt` char(16) NOT NULL,`kills` mediumint(8) NOT NULL DEFAULT '0',`deaths` mediumint(8) NOT NULL DEFAULT '0',`x` float NOT NULL DEFAULT '0',`y` float NOT NULL DEFAULT '0',`z` float NOT NULL DEFAULT '0',`angle` float NOT NULL DEFAULT '0',`interior` tinyint(3) NOT NULL DEFAULT '0', PRIMARY KEY (`id`), UNIQUE KEY `username` (`username`))");
	return 1;
}

UpdatePlayerData(playerid, reason)
{
	if (PlayerData[playerid][IsLoggedIn] == false) return 0;

	// if the client crashed, it's not possible to get the player's position in OnPlayerDisconnect callback
	// so we will use the last saved position (in case of a player who registered and crashed/kicked, the position will be the default spawn point)
	if (reason == 1)
	{
		GetPlayerPos(playerid, PlayerData[playerid][X_Pos], PlayerData[playerid][Y_Pos], PlayerData[playerid][Z_Pos]);
		GetPlayerFacingAngle(playerid, PlayerData[playerid][A_Pos]);
	}
	
	new query[145];
	mysql_format(g_SQL, query, sizeof query, "UPDATE `players` SET `x` = %f, `y` = %f, `z` = %f, `angle` = %f, `interior` = %d WHERE `id` = %d LIMIT 1", PlayerData[playerid][X_Pos], PlayerData[playerid][Y_Pos], PlayerData[playerid][Z_Pos], PlayerData[playerid][A_Pos], GetPlayerInterior(playerid), PlayerData[playerid][ID]);
	mysql_tquery(g_SQL, query);
	return 1;
}

UpdatePlayerDeaths(playerid)
{
	if (PlayerData[playerid][IsLoggedIn] == false) return 0;
	
	PlayerData[playerid][Deaths]++;
	
	new query[70];
	mysql_format(g_SQL, query, sizeof query, "UPDATE `players` SET `deaths` = %d WHERE `id` = %d LIMIT 1", PlayerData[playerid][Deaths], PlayerData[playerid][ID]);
	mysql_tquery(g_SQL, query);
	return 1;
}

UpdatePlayerKills(killerid)
{
	// we must check before if the killer wasn't valid (connected) player to avoid run time error 4
	if (killerid == INVALID_PLAYER_ID) return 0;
	if (PlayerData[killerid][IsLoggedIn] == false) return 0;
	
	PlayerData[killerid][Kills]++;
	
	new query[70];
	mysql_format(g_SQL, query, sizeof query, "UPDATE `players` SET `kills` = %d WHERE `id` = %d LIMIT 1", PlayerData[killerid][Kills], PlayerData[killerid][ID]);
	mysql_tquery(g_SQL, query);
	return 1;
}

CMD:makehelper(playerid, params[])
{
	new targetid, level;
	if(!IsPlayerAdmin(playerid)) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti admin!");
	if(sscanf(params, "ui", targetid, level)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /makehelper <jucator> <level>");
	if(level < 0 || level > 2) return SendClientMessage(playerid, COLOR_FADE1, "Eroare: Level-ul introdus este incorect.");
	
	PlayerData[targetid][HelperLevel] = level;
	new query[70];
	mysql_format(g_SQL, query, sizeof query, "UPDATE `players` SET `HelperLevel` = %d WHERE `id` = %d LIMIT 1", PlayerData[targetid][HelperLevel], PlayerData[targetid][ID]);
	mysql_tquery(g_SQL, query);
	
	new string[128];
	format(string, sizeof(string), "Ai dat helper level %d lui %s (%d)", level, PlayerData[targetid][Name], targetid);
	SendClientMessage(playerid, COLOR_ADMCHAT, string);
	
	format(string, sizeof(string), "Ai primit helper level %d de la %s (%d)", level, PlayerData[playerid][Name], playerid);
	SendClientMessage(targetid, COLOR_ADMCHAT, string);
	return 1;
}

CMD:hc(playerid, params[])
{
	new message[128];
	if(PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti helper!");
	if(sscanf(params, "s[128]", message)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /hc <mesaj>");
	
	new string[128];
	format(string, sizeof(string), "HLevel %d %s (%d): %s", PlayerData[playerid][HelperLevel], PlayerData[playerid][Name], playerid, message);
	HBroadCast(COLOR_ADMCHAT, string);
	
	return 1;
}


CMD:hduty(playerid, params[])
{
	new string[128];
	if(PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti helper!");
	if(HelperDuty[playerid] == 0)
	{
		format(string, sizeof(string), "Helper %s (%d) este acum ON-DUTY. Scrieti /needhelp sau /n pentru ajutor", PlayerData[playerid][Name], playerid);
		HelperDuty[playerid] = 1;
	}
	else
	{
		format(string, sizeof(string), "Helper %s (%d) este acum OFF-DUTY.", PlayerData[playerid][Name], playerid);
		HelperDuty[playerid] = 0;
	}
	SendClientMessageToAll(COLOR_LIGHTBLUE, string);
	return 1;
}

CMD:helpers(playerid, params[])
{
	new string[128];
	new total = 0, totalDuty = 0;
	SendClientMessage(playerid, COLOR_OOC, "Helpers Online:");
	foreach(new i: Player)
	{
		if(PlayerData[i][HelperLevel] > 0)
		{
			if(HelperDuty[i] == 1)
			{
				format(string, sizeof(string), "Helper Level %d %s (%d) - ON DUTY", PlayerData[i][HelperLevel], PlayerData[i][Name], i);
				totalDuty++;
			}
			else
				format(string, sizeof(string), "Helper Level %d %s (%d)", PlayerData[i][HelperLevel], PlayerData[i][Name], i);
			SendClientMessage(playerid, COLOR_OOC, string);
			
			total++;
		}
	}
	format(string, sizeof(string), "In total sunt %d helperi (din care %d ON-DUTY)",total, totalDuty);
	SendClientMessage(playerid, COLOR_OOC, string);
	return 1;
}

CMD:needhelp(playerid, params[])
{
	new message[128];
	new string[128];
	if(sscanf(params, "s[128]", message)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /needhelp <mesaj>");
	
	format(string, sizeof(string), "%s (%d) intreaba: %s", PlayerData[playerid][Name], playerid, message);
	HBroadCast(COLOR_ADMCHAT, string);
	
	SendClientMessage(playerid, COLOR_ADMCHAT, "Intrebarea ta a fost trimisa");
	return 1;
}

CMD:n(playerid, params[])
{
	new message[128];
	if(sscanf(params, "s[128]", message)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /n <mesaj>");
	if(HelperAtribuit[playerid] != -1) return SendClientMessage(playerid, COLOR_LIGHTRED, "Ai deja un helper atribuit!");
	
	IntrebareStocata[playerid] = message;
	
	CautaHelper(playerid);
	return 1;
}

CMD:ar(playerid, params[])
{
	new jucatorAtribuit;
	if(PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti helper!");
	if(HelperOcupat[playerid] == -1) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu ai atribuit nici un jucator!");
	if(ConversatieOpen[playerid] == 1) return SendClientMessage(playerid, COLOR_LIGHTRED, "Ai acceptat deja cererea.");
	
	jucatorAtribuit = HelperOcupat[playerid];
	SendClientMessage(jucatorAtribuit, COLOR_YELLOW, "Cererea ta a fost acceptata, poti vorbii prin /hl");
	
	SendClientMessage(playerid, COLOR_YELLOW, "Ai acceptat cererea.");
	
	ConversatieOpen[playerid] = 1;
	return 1;
}

CMD:cr(playerid, params[])
{
	new message[128];
	if(PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti helper!");
	if(HelperOcupat[playerid] == -1) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu ai atribuit nici un jucator!");
	if(sscanf(params, "s[128]", message)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /cr <motiv>");
	
	new jucatorAtribuit = HelperOcupat[playerid];
	
	if(ConversatieOpen[playerid] == 1)
	{
		new string[128];
		format(string, sizeof(string), "Helperul %s (%d) a inchis conversatia cu tine. Mesaj: %s", PlayerData[playerid][Name], playerid, message);
		SendClientMessage(jucatorAtribuit, COLOR_YELLOW, string);
		
		format(string, sizeof(string), "Ai inchis conversatia cu %s (%d). Mesaj: %s", PlayerData[jucatorAtribuit], jucatorAtribuit, message);
		SendClientMessage(playerid, COLOR_YELLOW, string);
		
		HelperOcupat[playerid] = -1;
		HelperAtribuit[jucatorAtribuit] = -1;
		
		ConversatieOpen[playerid] = 0;
	}
	else
	{
		new string[128];
		format(string, sizeof(string), "Helper %s (%d): %s", PlayerData[playerid][Name], playerid, message);
		SendClientMessage(jucatorAtribuit, COLOR_ADMCHAT, string);
		
		format(string, sizeof(string), "%s (%d) intreaba: %s", PlayerData[jucatorAtribuit][Name], jucatorAtribuit, IntrebareStocata[jucatorAtribuit]);
		SendClientMessageToAll(COLOR_ADMCHAT, string);
		
		format(string, sizeof(string), "%s (%d) a raspuns: %s", PlayerData[playerid][Name], playerid, message);
		SendClientMessageToAll(COLOR_ADMCHAT, string);
		
		HelperOcupat[playerid] = -1;
		HelperAtribuit[jucatorAtribuit] = -1;
	}
	return 1;
}

CMD:hl(playerid, params[])
{
	new message[128];
	if(HelperOcupat[playerid] == -1 && PlayerData[playerid][HelperLevel] > 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Eroare: Niciun jucator nu ti-a fost atribuit.");
	if(HelperAtribuit[playerid] == -1 && PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Eroare: Niciun helper nu ti-a fost atribuit.");
	if(PlayerData[playerid][HelperLevel] == 0 && ConversatieOpen[ HelperAtribuit[playerid] ] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Eroare: Helperul nu a deschis conversatia cu tine.");
	if(PlayerData[playerid][HelperLevel] > 0 && ConversatieOpen[playerid] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Eroare: Nu ai deschis prin /ar conversatia cu jucatorul.");
	
	if(sscanf(params, "s[128]", message)) return SendClientMessage(playerid, COLOR_FADE1, "Utilizare: /hl <mesaj>");
	
	new string[128];
	if(PlayerData[playerid][HelperLevel] > 0)
	{//Tasteaza helper
		new jucatorAtribuit = HelperOcupat[playerid];
		format(string, sizeof(string), "Helper %s (%d): %s", PlayerData[playerid][Name], playerid, message);
		SendClientMessage(playerid, COLOR_LIGHTBLUE, string);
		
		SendClientMessage(jucatorAtribuit, COLOR_LIGHTBLUE, string);
	}
	else
	{//Tasteaza jucatorul
		new helperAtribuit = HelperAtribuit[playerid];
		format(string, sizeof(string), "Jucator %s (%d): %s", PlayerData[playerid][Name], playerid, message);
		SendClientMessage(playerid, COLOR_LIGHTBLUE, string);
		
		SendClientMessage(helperAtribuit, COLOR_LIGHTBLUE, string);
	}
	return 1;
}

CMD:skipn(playerid, params[])
{
	new jucatorAtribuit;
	if(PlayerData[playerid][HelperLevel] == 0) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu esti helper!");
	if(HelperOcupat[playerid] == -1) return SendClientMessage(playerid, COLOR_LIGHTRED, "Nu ai atribuit nici un jucator!");
	
	jucatorAtribuit = HelperOcupat[playerid];
	CautaHelperNou(jucatorAtribuit, 0);
	return 1;
}

forward CautaHelperNou(playerid, reason);
public CautaHelperNou(playerid, reason)
{
	new string[128];
	new helperAtribuit = HelperAtribuit[playerid];
	if(reason == 0)
	{// In caz de /skipn
		format(string, sizeof(string), "Helperul %s (%d) a tastat /skipn. Se cauta un nou helper", PlayerData[helperAtribuit][Name], helperAtribuit);
		SendClientMessage(playerid, COLOR_YELLOW, string);
		
		format(string, sizeof(string), "Ai anulat cererea lui %s (%d).", PlayerData[playerid][Name], playerid);
		SendClientMessage(helperAtribuit, COLOR_YELLOW, string);
	}
	else
	{// In caz de Timer
		format(string, sizeof(string), "Helperul %s (%d) nu a raspuns in 30 de secunde. Se cauta un nou helper.", PlayerData[helperAtribuit][Name], helperAtribuit);
		SendClientMessage(playerid, COLOR_YELLOW, string);
		
		format(string, sizeof(string), "Nu ai raspuns in 30 de secunde lui %s (%d).", PlayerData[playerid][Name], playerid);
		SendClientMessage(helperAtribuit, COLOR_YELLOW, string);
	}
	
	CautaHelper(playerid);
	HelperOcupat[helperAtribuit] = -1;
	HelperAtribuit[playerid] = -1;
}

stock CautaHelper(playerid)
{
	new string[128];
	new gasit = 0;
	foreach(new i: Player)
	{
		if(PlayerData[i][HelperLevel] > 0 && HelperDuty[i] == 1 && HelperOcupat[i] == -1)
		{//Am gasit helper
			gasit = 1;
			
			format(string, sizeof(string), "Cererea ta a fost trimisa catre %s (%d). Asteapta un raspuns.", PlayerData[i][Name], i);
			SendClientMessage(playerid, COLOR_ADMCHAT, string);
			
			format(string, sizeof(string), "O noua cerere de la %s (%d) << %s >>", PlayerData[playerid][Name], playerid, IntrebareStocata[playerid]);
			SendClientMessage(i, COLOR_YELLOW, string);
			
			SendClientMessage(i, COLOR_YELLOW, "Scrie /ar pentru a accepta /skipn pentru a anula. Dupa ce ai terminat scrie /cr");
			SendClientMessage(i, COLOR_YELLOW, "Ai 30 de secunde pentru a accepta.");
			
			HelperOcupat[i] = playerid;
			HelperAtribuit[playerid] = i;
			
			HelpMeTimer[playerid] = SetTimerEx("CautaHelperNou", 10 * 1000, false, "ii", playerid, 1);
		}
		
		if(gasit == 1)
			break;
	}
	if(gasit == 0)
		SendClientMessage(playerid, COLOR_LIGHTRED, "Nici un helper disponibil momentan");
}

stock HBroadCast(color, string[])
{
	foreach(new i: Player)
	{
		if(PlayerData[i][HelperLevel] > 0)
			SendClientMessage(i, color, string);
	}
}