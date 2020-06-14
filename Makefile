all:
	./scripting/spcomp scripting/autojoin.sp 
	mkdir -p plugins/
	mv autojoin.smx plugins/
clean:
	rm plugins/autojoin.smx
