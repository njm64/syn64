BUILD=build
D64=${BUILD}/synacor.d64
PRG=${BUILD}/vm.prg
MAKEDISK=${BUILD}/makedisk
CHALLENGE=synacor/challenge.bin

${D64}: ${PRG} ${MAKEDISK} ${CHALLENGE}
	${MAKEDISK} ${CHALLENGE} ${PRG} $@

${MAKEDISK}: tools/makedisk.c
	${CC} $< -o $@

${PRG}: *.asm
	java -jar ~/kick/kickass.jar vm.asm -vicesymbols -odir ${BUILD}

clean: 
	rm -rf ${BUILD}
