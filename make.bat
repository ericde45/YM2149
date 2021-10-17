@echo off
clear
del build\test.bin
copy vectorball2.asm C:\Users\Eric\projects\ARM3D\ARM3D /Y
copy rmrebuild.asm C:\Users\Eric\projects\ARM3D\ARM3D /Y
copy fiqRM2.asm C:\Users\Eric\projects\ARM3D\ARM3D /Y
copy fiqRMdist.asm C:\Users\Eric\projects\ARM3D\ARM3D /Y
copy lsp.asm C:\Users\Eric\projects\ARM3D\ARM3D /Y

rem vasmarm_std_win32.exe -L compile.txt -linedebug -m250 -Fbin -opt-adr -o build\test.bin vectorball2.asm
rem vasmarm_std_win32.exe -L compiletest.txt -linedebug -m250 -Fbin -opt-adr  -o build\test.bin dist1.asm
rem vasmarm_std_win32.exe -L compile.txt -linedebug -m250 -Fbin -o build\320x200.bin 320x200.asm
vasmarm_std_win32.exe -L compileYM2.txt -linedebug -m250 -Fbin -o build\ym.bin ym2.asm
rem vasmarm_std_win32.exe -L compilelha.txt -linedebug -m250  -Fbin -o build\lha.bin lha.asm


rem vasmarm_std_win32.exe -L compileFIQ2.txt -linedebug -m250 -Fbin -o build\fiqrmi2.bin fiqRM2.asm
vasmarm_std_win32.exe -L compileFIQ2.txt -linedebug -m250 -Fbin -o build\fiqrmidist.bin fiqRMdist.asm

rem vasmarm_std_win32.exe -L compileRMI.txt -linedebug -m250 -Fbin -o build\rmi.bin rmrebuild.asm

rem vasmarm_std_win32.exe -L compiletest.txt -linedebug -m250 -Fbin -opt-adr  -o build\test.bin lsp.asm
rem vasmarm_std_win32.exe -L compiletest.txt -linedebug -m250 -Fbin -opt-adr  -o build\playsample.bin playsample.asm

rem tfmx
rem vasmarm_std_win32.exe -L compiletfmx.txt -linedebug -m250 -Fbin -opt-adr  -o build\tfmx.bin tfmx.asm

rem vasmarm_std_win32.exe -L compileelf.txt -m250 -Felf -opt-adr -o build\test.elf test.asm
rem copy build\test.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\test,ff8"
rem copy build\test.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\test"
copy build\rmi.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\rmi,ff8"
rem copy build\\playsample.bin  "C:\Archi\Arculator_V2.0_Windows\hostfs\psa,ff8"
rem copy build\rmi.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\rmi"
rem copy build\320x200.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\320200,ff8"
copy build\ym.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\ym,ff8"
rem copy build\lha.bin "C:\Archi\Arculator_V2.0_Windows\hostfs\lha,ff8"

rem tfmx
rem copy build\\tfmx.bin  "C:\Archi\Arculator_V2.0_Windows\hostfs\tfmx,ff8"