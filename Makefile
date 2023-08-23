novika = bin/novika
runnables = console disk ffi sdl

payload.json:
	$(novika) $(runnables) json-docs.nk | python util/nkdoc.py > payload.json
