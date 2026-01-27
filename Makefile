all: deploy

# ./terraform/Makefile
plan:
	$(MAKE) -C ./terraform $(@)

init:
	$(MAKE) -C ./terraform $(@)

reconfigure upgrade:
	$(MAKE) -C ./terraform $(@)

refresh validate fmt:
	$(MAKE) -C ./terraform $(@)

apply:
	$(MAKE) -C ./terraform $(@)

update:
	$(MAKE) -C ./terraform $(@)

output:
	$(MAKE) -C ./terraform $(@)


# ./landing_page/Makefile
# ./application/Makefile
deploy:
	$(MAKE) -C ./landing_page $(@)
	$(MAKE) -C ./application $(@)

.PHONY: plan init reconfigure upgrade refresh validate fmt apply approve output deploy
