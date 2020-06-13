all:
	./scripting/spcomp scripting/autojoin.sp 
	mv autojoin.smx plugins/
clean:
	rm plugins/autojoin.smx
