all:
	./scripting/spcomp scripting/autojoin.sp 
	mv scripting/autojoin.smx plugins/
clean:
	rm plugins/autojoin.smx