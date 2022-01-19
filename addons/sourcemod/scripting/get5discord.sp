#include "include/get5.inc"
#include <cstrike>
#include <sdktools>
#include <sourcemod>

#include "get5/util.sp"

#include <json>  // github.com/clugg/sm-json

#pragma dynamic 131072

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>

char g_webhookURL[1024];
char g_Username[1024] = "Match Result Bot";
char g_AvatarUrl[1024] = "https://i.imgur.com/rHYHg0j.png";
int g_Color = 39423;


public Plugin myinfo = {
    name = "Get5 Discord Integration",
    author = "Ferex",
    description = "Records match results to a Discord channel",
    version = "1.0.0",
    url = "https://github.com/Ferexx/get5discord"
};

public void OnPluginStart() {
    RegAdminCmd("setWebhookUrl", Command_SetURL, ADMFLAG_CHANGEMAP,
        "Set the Discord Webhook URL for where the results will be posted. URLs should begin with: https://discord.com/api/webhooks/");
    RegAdminCmd("setUsername", Command_SetUsername, ADMFLAG_CHANGEMAP,
        "Set the Username that will show up when results are posted in Discord.");
    RegAdminCmd("setAvatarUrl", Command_SetAvatarUrl, ADMFLAG_CHANGEMAP,
        "Set the Profile Picture that will show up when results are posted in Discord.");
    RegAdminCmd("setColor", Command_SetColor, ADMFLAG_CHANGEMAP,
        "Set the color of the sidebar on the results.");

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/get5discord.cfg");

    if (!FileExists(path)) {
        WriteConfigFile();
    } else {
        LogMessage("Found get5discord.cfg file. Loading...");
        File file = OpenFile(path, "r");
        char buffer[1024];
        char split[2][1024];

        file.ReadLine(buffer, sizeof(buffer));
        ExplodeString(buffer, "URL:", split, sizeof(split), sizeof(split[]));

        if (StrEqual(split[0], "webhook")) {
            ReplaceString(split[1], sizeof(split[]), "\n", "");
            strcopy(g_webhookURL, sizeof(g_webhookURL), split[1]);
            LogMessage("Webhook URL set to %s", g_webhookURL);
        } else {
            LogError("Incorrectly formatted .cfg file, failed to load webhook URL.");
        }

        file.ReadLine(buffer, sizeof(buffer));
        ExplodeString(buffer, ":", split, sizeof(split), sizeof(split[]));

        if (StrEqual(split[0], "username")) {
            ReplaceString(split[1], sizeof(split[]), "\n", "");
            strcopy(g_Username, sizeof(g_Username), split[1]);
            LogMessage("Username set to %s", g_Username);
        } else {
            LogError("Incorrectly formatted .cfg file, failed to load username.");
        }

        file.ReadLine(buffer, sizeof(buffer));
        ExplodeString(buffer, "URL:", split, sizeof(split), sizeof(split[]));

        if (StrEqual(split[0], "avatar")) {
            ReplaceString(split[1], sizeof(split[]), "\n", "");
            strcopy(g_AvatarUrl, sizeof(g_AvatarUrl), split[1]);
            LogMessage("Avatar URL set to %s", g_AvatarUrl);
        } else {
            LogError("Incorrectly formatted .cfg file, failed to load avatar URL.");
        }

        file.ReadLine(buffer, sizeof(buffer));
        ExplodeString(buffer, ":", split, sizeof(split), sizeof(split[]));

        if (StrEqual(split[0], "color")) {
            ReplaceString(split[1], sizeof(split[]), "\n", "");
            g_Color = StringToInt(split[1]);
            LogMessage("Color set to %d", g_Color);
        } else {
            LogError("Incorrectly formatted .cfg file, failed to load color.");
        }

        delete file;
    }
}

public Action Command_SetURL(int client, int args) {
    GetCmdArg(1, g_webhookURL, sizeof(g_webhookURL));
    PrintToConsole(client, "URL set.");

    WriteConfigFile();
}

public Action Command_SetUsername(int client, int args) {
    GetCmdArg(1, g_Username, sizeof(g_Username));
    PrintToConsole(client, "Username set.");

    WriteConfigFile();
}

public Action Command_SetAvatarUrl(int client, int args) {
    GetCmdArg(1, g_AvatarUrl, sizeof(g_AvatarUrl));
    PrintToConsole(client, "Avatar URL set.");

    WriteConfigFile();
}

public Action Command_SetColor(int client, int args) {
    char buffer[1024];
    GetCmdArg(1, buffer, sizeof(buffer));
    g_Color = StringToInt(buffer);

    WriteConfigFile();
}

public void Get5_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score, int mapNumber) {
    char winnerString[64];
    GetTeamString(mapWinner, winnerString, sizeof(winnerString));
    
    CreateMatchEndRequests(map, mapNumber);
}

public void CreateMatchEndRequests(const char[] map, int mapNumber) {
    char t1name[64], t2name[64];
    FindConVar("mp_teamname_1").GetString(t1name, sizeof(t1name));
    int t1score = CS_GetTeamScore(Get5_MatchTeamToCSTeam(MatchTeam_Team1));
    FindConVar("mp_teamname_2").GetString(t2name, sizeof(t2name));
    int t2score = CS_GetTeamScore(Get5_MatchTeamToCSTeam(MatchTeam_Team2));

    // Begin JSON
    JSON_Object hObj = new JSON_Object();
    hObj.SetString("username", g_Username);
    hObj.SetString("avatar_url", g_AvatarUrl);

    // Create embed array   
    JSON_Array embedsArray = new JSON_Array();

    // Create embed and add match info
    JSON_Object embed = new JSON_Object();
    char buffer[1024];

    JSON_Object author = new JSON_Object();
    Format(buffer, sizeof(buffer), "Match on %s", map);
    author.SetString("name", buffer);
    embed.SetObject("author", author);

    embed.SetInt("color", g_Color);

    Format(buffer, sizeof(buffer), "%s %d-%d %s", t1name, t1score, t2score, t2name);
    embed.SetString("title", buffer);

    // Add players
    JSON_Array hPlayers = new JSON_Array();
    KeyValues kv = new KeyValues("Stats");
    Get5_GetMatchStats(kv);

    char mapKey[32];
    Format(mapKey, sizeof(mapKey), "map%d", mapNumber + 1);

    if (kv.JumpToKey(mapKey)) {
        if (kv.JumpToKey("team1")) {
            JSON_Object hPlayer = AddStatsToJson(kv, MatchTeam_Team1);
            hPlayers.PushObject(hPlayer);
            kv.GoBack();
        }
        if (kv.JumpToKey("team2")) {
            JSON_Object hPlayer = AddStatsToJson(kv, MatchTeam_Team2);
            hPlayers.PushObject(hPlayer);
            kv.GoBack();
        }
        kv.GoBack();
    }
    else {
        Format(mapKey, sizeof(mapKey), "map%d", mapNumber);
        kv.JumpToKey(mapKey)
        if (kv.JumpToKey("team1")) {
            JSON_Object hPlayer = AddStatsToJson(kv, MatchTeam_Team1);
            hPlayers.PushObject(hPlayer);
            kv.GoBack();
        }
        if (kv.JumpToKey("team2")) {
            JSON_Object hPlayer = AddStatsToJson(kv, MatchTeam_Team2);
            hPlayers.PushObject(hPlayer);
            kv.GoBack();
        }
        kv.GoBack();
    }
    delete kv;

    embed.SetObject("fields", hPlayers);

    // Add thumbnail
    JSON_Object thumbnail = new JSON_Object();
    thumbnail.SetString("url", "https://i.imgur.com/qCYQGjv.jpg");
    embed.SetObject("thumbnail", thumbnail);

    // Add footer
    JSON_Object footer = new JSON_Object();
    footer.SetString("text", "Bot provided by Ferex");
    footer.SetString("icon_url", "https://i.imgur.com/yCw3yxZ.jpg");
    embed.SetObject("footer", footer);

    embedsArray.PushObject(embed);
    hObj.SetObject("embeds", embedsArray);

    // Send webhook
    char JSON_DUMP[8192];
    hObj.Encode(JSON_DUMP, sizeof(JSON_DUMP));
    PrintToServer("%s", JSON_DUMP);

    Handle req = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, g_webhookURL);

    if (req != INVALID_HANDLE) {
        SteamWorks_SetHTTPRequestRawPostBody(req, "application/json", JSON_DUMP, strlen(JSON_DUMP));
        SteamWorks_SendHTTPRequest(req);
    }
    delete req;
    json_cleanup_and_delete(hObj);
}

public JSON_Object AddStatsToJson(KeyValues kv, MatchTeam team) {
    JSON_Object hPlayer = new JSON_Object();
    if (kv.GotoFirstSubKey()) {
        do {
            char auth[AUTH_LENGTH];
            kv.GetSectionName(auth, sizeof(auth));

            char playerName[MAX_NAME_LENGTH];
            kv.GetString("name", playerName, sizeof(playerName));

            char teamString[16];
            GetTeamString(team, teamString, sizeof(teamString));

            hPlayer.SetString("name", playerName);

            char statsString[1024];
            Format(statsString, sizeof(statsString), "Kills: %d\nAssists: %d\nDeaths: %d", kv.GetNum(STAT_KILLS), kv.GetNum(STAT_ASSISTS), kv.GetNum(STAT_DEATHS));
            hPlayer.SetString("value", statsString);

            /*AddIntStat(req, kv, STAT_KILLS);
            AddIntStat(req, kv, STAT_DEATHS);
            AddIntStat(req, kv, STAT_ASSISTS);
            AddIntStat(req, kv, STAT_FLASHBANG_ASSISTS);
            AddIntStat(req, kv, STAT_TEAMKILLS);
            AddIntStat(req, kv, STAT_SUICIDES);
            AddIntStat(req, kv, STAT_DAMAGE);
            AddIntStat(req, kv, STAT_HEADSHOT_KILLS);
            AddIntStat(req, kv, STAT_ROUNDSPLAYED);
            AddIntStat(req, kv, STAT_BOMBPLANTS);
            AddIntStat(req, kv, STAT_BOMBDEFUSES);
            AddIntStat(req, kv, STAT_1K);
            AddIntStat(req, kv, STAT_2K);
            AddIntStat(req, kv, STAT_3K);
            AddIntStat(req, kv, STAT_4K);
            AddIntStat(req, kv, STAT_5K);
            AddIntStat(req, kv, STAT_V1);
            AddIntStat(req, kv, STAT_V2);
            AddIntStat(req, kv, STAT_V3);
            AddIntStat(req, kv, STAT_V4);
            AddIntStat(req, kv, STAT_V5);
            AddIntStat(req, kv, STAT_FIRSTKILL_T);
            AddIntStat(req, kv, STAT_FIRSTKILL_CT);
            AddIntStat(req, kv, STAT_FIRSTDEATH_T);
            AddIntStat(req, kv, STAT_FIRSTDEATH_CT);
            AddIntStat(req, kv, STAT_TRADEKILL);
            AddIntStat(req, kv, STAT_KAST);
            AddIntStat(req, kv, STAT_CONTRIBUTION_SCORE);*/
        } while (kv.GotoNextKey());
        kv.GoBack();
    }
    return hPlayer;
}

public void WriteConfigFile() {
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/get5discord.cfg");

    File file = OpenFile(path, "w");

    file.WriteLine("webhookURL:%s", g_webhookURL);
    file.WriteLine("username:%s", g_Username);
    file.WriteLine("avatarURL:%s", g_AvatarUrl);
    file.WriteLine("color:%d", g_Color);

    delete file;
}