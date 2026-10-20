@echo off
rem Runs the unit tests in tests\ (see tests\run.lua). Set LUA to your Lua
rem 5.1 interpreter if it isn't at the default install path. Pass a test
rem file to run just that one: test.bat tests\test_noxiousWeeds.lua
cd /d "%~dp0"
if "%LUA%"=="" set "LUA=C:\Program Files (x86)\Lua\5.1\lua.exe"
"%LUA%" tests\run.lua %*
