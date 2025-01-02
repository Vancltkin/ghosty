#!/bin/bash

# Папки для LuCI
mkdir -p /usr/lib/lua/luci/controller/singbox
mkdir -p /usr/lib/lua/luci/model/cbi/singbox
mkdir -p /usr/lib/lua/luci/view/singbox
mkdir -p /etc/sing-box/profiles

# Создание контроллера
cat > /usr/lib/lua/luci/controller/singbox.lua << 'EOF'
module("luci.controller.singbox", package.seeall)

function index()
    entry({"admin", "services", "singbox"}, firstchild(), _("Settings-Singbox"), 100).dependent = false
    entry({"admin", "services", "singbox", "config"}, cbi("singbox/config"), _("Edit Config"), 1)
    entry({"admin", "services", "singbox", "profiles"}, template("singbox/profiles"), _("Profiles"), 2)
end
EOF

# Модель для редактирования config.json
cat > /usr/lib/lua/luci/model/cbi/singbox/config.lua << 'EOF'
local fs = require "nixio.fs"

m = SimpleForm("singbox", translate("Singbox Config"), translate("Edit and save the Singbox configuration."))

local config_path = "/etc/sing-box/config.json"
local profiles_path = "/etc/sing-box/profiles"

-- Прочитать текущий конфиг
local current_config = fs.readfile(config_path) or ""

-- Поле для редактирования конфига
config = m:field(TextValue, "config")
config.rmempty = false
config.rows = 20
config.description = translate("Edit the JSON configuration below.")
config.default = current_config

-- Сохранить изменения
function m.handle(self, state, data)
    if state == FORM_VALID then
        fs.writefile(config_path, data.config)
        local active_profile = fs.readfile(profiles_path .. "/active_profile") or "default"
        fs.writefile(profiles_path .. "/" .. active_profile .. ".json", data.config)
    end
    return true
end

-- Кнопка для сохранения в новый профиль
save_as_profile = m:field(Value, "save_as_profile", translate("Save as Profile"))
save_as_profile.placeholder = translate("Enter profile name")

function save_as_profile.write(self, section, value)
    if value and value:match("^[a-zA-Z0-9_-]+$") then
        local profile_path = profiles_path .. "/" .. value .. ".json"
        fs.writefile(profile_path, fs.readfile(config_path))
        fs.writefile(profiles_path .. "/active_profile", value)
    end
end

return m
EOF

# Шаблон для работы с профилями
cat > /usr/lib/lua/luci/view/singbox/profiles.htm << 'EOF'
<h2>Profiles</h2>
<p>Select a profile to view, apply, or delete.</p>

<%+
local fs = require "nixio.fs"
local profiles_path = "/etc/sing-box/profiles"
local profiles = fs.dir(profiles_path) or {}
%>

<form method="post" action="">
    <select name="profile">
        <% for _, profile in ipairs(profiles) do
            if profile ~= "active_profile" then
        %>
            <option value="<%=profile%>"><%=profile%></option>
        <% end end %>
    </select>
    <button type="submit" name="action" value="view">View</button>
    <button type="submit" name="action" value="apply">Apply</button>
    <button type="submit" name="action" value="delete">Delete</button>
</form>

<% 
if luci.http.formvalue("action") == "view" and luci.http.formvalue("profile") then
    local profile = luci.http.formvalue("profile")
    luci.template.render_string("<pre>" .. fs.readfile(profiles_path .. "/" .. profile) .. "</pre>")
end

if luci.http.formvalue("action") == "apply" and luci.http.formvalue("profile") then
    local profile = luci.http.formvalue("profile")
    fs.writefile("/etc/sing-box/config.json", fs.readfile(profiles_path .. "/" .. profile))
    fs.writefile(profiles_path .. "/active_profile", profile)
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "singbox", "config"))
end

if luci.http.formvalue("action") == "delete" and luci.http.formvalue("profile") then
    local profile = luci.http.formvalue("profile")
    fs.remove(profiles_path .. "/" .. profile)
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "singbox", "profiles"))
end
%>
EOF

# Перезапуск веб-интерфейса
/etc/init.d/uhttpd restart
echo "Singbox LuCI module has been installed successfully."
