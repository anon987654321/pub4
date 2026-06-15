@echo off
C:\cygwin64\bin\ruby.exe -e "require 'win32ole'; v=WIN32OLE.new('SAPI.SpVoice'); v.Rate=0; v.Volume=100; v.Speak('%*', 0)"

