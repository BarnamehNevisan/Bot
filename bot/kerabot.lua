package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

VERSION = '2'

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  local receiver = get_receiver(msg)
  print (receiver)

  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < now then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
  	local login_group_id = 1
  	--It will send login codes to this chat
    send_large_msg('chat#id'..login_group_id, msg.text)
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end

  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "info",
    "antilink",
    "auto_leave",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "arabic_lock",
    "set",
    "get",
    "broadcast",
    "download_media",
    "invite",
    "all",
    "leave_ban",
    "admin",
    "welcome",
    "sms",
    "calc",
    "spam"
    },
    sudo_users = {120816252,147191022},--Sudo users
    disabled_channels = {},
    moderation = {data = 'data/moderation.json'},
    about_text = [[Kerabot v2.1 - Open Source
ادمین ها
@keraboy
@mohammadslayer 

کانال تیم ما : @Kerach
]],
    help_text_realm = [[
دستورات گروه تخصصی :

ساخت گروه  [اسم]
یک گروه میسازد

ساخت گروه تخصصی [اسم]
گروه تخصصی میسازد

تنظیم نام [اسم]
تنظیم نام گروه تخصصی

تنظیم مشخصات [آیدی گروه] [مشخصات]
تنظیم مشخصات گروه مورد نظر

تنظیم قوانین [آیدی گروه] [قوانین]
تنظیم قوانین گروه مورد نظر

قفل [آیدی گروه] [تنظیمات ]
قفل تنظیمات گروه مورو نظر

بازکردن [آیدی گروه] [تنظیمات]
بازکردن قفل تنظیمات گروه مورد نظر

افراد گروه
دریافت لیستی از افراد گروه / گروه تخصصی

افراد گروه.
دریافت فایلی از افراد گروه / گروه تخصصی

الگو
دریافت الگوی گروع

از بین ببر [آیدی گروه]
از بین بردن تمام اعضا و حذف گروه مورد نظر

از بین ببر [آیدی گروه تخصصی]
از بین بردن تمام اعضا و حذف گروه تخصصی

اضافه کردن مدیر [آیدی یا یوزرنیم]
ترفیع یک ادمین با آیدی یا یوزرنیم (فقط سودو)

از بین بردن مدیر [آیدی یا یوزرنیم]
تنزیل یک مدیر با آیدی یا یوزرنیم (فق‌ سودو) 

لیست گروه ها
دریافت لیستی از تمام گرو ها

لیست گروه های تخصصی
دریافت لیستی از تمام گروه های تخصصی

لیست
دریافت فایلی از لیست گروه ها / گروه های تخصصی

ارسال به همه [متن]
ارسال به همه سلام (مثال)
ارسال متن به همه گروه ها
فقط سودو ها میتوانند این دستور را اجرا کنند

!bc [آیدی گروه] [متن]
!bc 123456789 سلام (مثال)
این دستور متن مورد نظر را به گروه مشخص شده ارسال میکند


*شما میتوانید دستور ها را هم با نقطه و هم بدون نقطه ارسال کنید 


*فقط ادمین و سودو میتواند ربات را به گروه دعوت کند


*فقط ادمین و سودو میتواند این دستور ها را اجرا کند
اخراج,بن,×بن,لینک جدید,تنظیم عکس,تنظیم نام,قفل,بازکردن,تنظیم قوانین,تنظیم مشخصات و تنظیمات دیگر

*فقط ادمین و سودو میتوانند از دستور های مشخصات (آیدی) و انتخاب مدیر اصلی , استفاده کند
]],
    help_text = [[
لیست دستورات :

اخراج [آیدی یا یوزرنیم]
شما میتوانید این دستور را با ریپلی نیز استفاده کنید

بن [آیدی یا یوزرنیم]
شما میتوانید این دستور را با ریپلی نیز استفاده کنید

×بن [آیدی]
شما میتوانید این دستور را با ریپلی نیز استفاده کنید

افراد گروه
لیست اعضا

مدیر ها
لیست کمک مدیر ها

ترفیع [یوزرنیم]
ترفیع یک ادمین

تنزیل [یوزرنیم]
تنزیل یک ادمین

خروج
از گروه خارج میشوید

مشخصات
مشخصات گروه

تنظیم عکس
تنظیم و قفل عکس گروه

تنظیم نام [اسم]
تنظیم اسم گروه

قوانین
قوانین گروه

آیدی
ارسال آیدی گروع یا شخص مورد نظر

راهنما

قفل [اعضا|اسم|ربات ها|خروج]	
قفل کردن [اعضا|اسم|ربات ها|خروج] 

بازکردن [اعضا|اسم|ربات ها|خروج]
بازکردن قفل [اعضا|اسم|ربات ها|خروج]

تنظیم قوانین <متن>
تنظیم <متن> به عنوان قوانین

تنظیم مشخصات <متن> 
تنظیم <متن> به عنوان مشخصات

تنظیمات
ارسال تنظیمات گروه

لینک جدید
ساخت / تغییر لینک گروه

لینک
ارسال لینک گروه

مدیر اصلی
ارسال آیدی مدیر اصلی گروه

تنظیم مدیر اصلی [آیدی]
آیدی مورد نظر را مدیر اصلی میکند

حساسیت [مقدار]
تنظیم مقدار مورد نظز برای حساسیت اخراج

آمار
ارسال آمار ساده

ذخیره [مقدار] <متن>
ذخیره <متن> به عنوان [مقدار]

دریافت [مقدار]
ارسال پیامی حاوی  [مقدار]

پاک کردن [مدیران|قوانین|مشخصات]
[مدیران|قوانین|مشخصات] را پاک میکند و به حال اول برمیگرداند

مشخصات [یوزرنیم]
ارسال مشخصات یوزرنین مورد نظز
"مشخصات @username" (مثال)

لیست
ارسال میکند لیست گروه را

لیست بن
ارسال میکند لیست بن ها را

*شما میتوانید دستور ها را هم با نقطه و هم بدون نقطه ارسال کنید 


*فقط ادمین و سودو میتواند ربات را به گروه دعوت کند


*فقط ادمین و سودو میتواند این دستور ها را اجرا کند
اخراج,بن,×بن,لینک جدید,تنظیم عکس,تنظیم نام,قفل,بازکردن,تنظیم قوانین,تنظیم مشخصات و تنظیمات دیگر

*فقط ادمین و سودو میتوانند از دستور های مشخصات (آیدی) و انتخاب مدیر اصلی , استفاده کند

]]
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)

end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
      print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end


-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
