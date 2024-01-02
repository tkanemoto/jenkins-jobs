SHELL       = /bin/bash
NO_COLOR    = \033[0m
COLOR       = \033[32;01m
SUCCESS_COLOR   = \033[35;01m
JJB_LOG_LEVEL ?= INFO
YAML_DIR ?= yaml
LOCAL_PATH := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
JENKINS_URL ?= https://ci.tkanemoto.com/
FILTER ?= '.*'

jenkins-name = $(subst /,,$(subst :,-,$(JENKINS_URL)))
secure-ini-path = $(LOCAL_PATH)/etc/secure.$(jenkins-name).ini

define get-config
$(if $(JENKINS_JOBS_CONFIG),$(JENKINS_JOBS_CONFIG), \
  $(if $(shell ls $(secure-ini-path) 2>/dev/null), \
    $(secure-ini-path),$(LOCAL_PATH)/etc/dummy.ini \
  ) \
)
endef

all: envsetup clean test

$(LOCAL_PATH)/xml:
	@mkdir -p $(LOCAL_PATH)/xml

.venv/bin/pipenv: .venv/bin/pip3
	$< install 'pipenv==2023.10.24'

.venv/bin/pip3:
	python3 -m venv .venv

test: envsetup $(LOCAL_PATH)/xml | .venv/bin/pipenv
	@echo -e "$(COLOR)* Testing YAML files in $(YAML_DIR)$(NO_COLOR)"
	@bash -c "\
      rm -f $(LOCAL_PATH)/xml/* && \
      $| run jenkins-jobs --conf $(call get-config) -l $(JJB_LOG_LEVEL) test $(YAML_DIR) -o $(LOCAL_PATH)/xml"
	@echo -e "$(COLOR)* The following Jenkins configuration files will be deployed when 'make update' ($(LOCAL_PATH)/xml)$(NO_COLOR)"
	@ls -l $(LOCAL_PATH)/xml
	@echo -e "$(SUCCESS_COLOR)Test passed :D$(NO_COLOR)"

update: test deployment-env | .venv/bin/pipenv
	@echo -e "$(COLOR)* Updating Jenkins using $(call get-config)$(NO_COLOR)"
	@bash -c "\
      $| run jenkins-jobs --conf $(call get-config) -l $(JJB_LOG_LEVEL) update $(YAML_DIR)"
	@echo -e "$(SUCCESS_COLOR)All done :D$(NO_COLOR)"

list-deleted: test deployment-env
	@echo -e "$(COLOR)* Jobs removed in $(LOCAL_PATH)/xml"
	@bash -c "\
      cd xml && \
      git ls-files --deleted | grep -e $(FILTER) | while read job ; do \
        PYTHONHTTPSVERIFY=0 \
        echo \$$job ; \
      done"

delete: test deployment-env
	@echo -e "$(COLOR)* Deleting jobs removed in $(LOCAL_PATH)/xml"
	bash -c "\
      cd xml && \
      git ls-files --deleted | grep -e $(FILTER) | while read job ; do \
        pipenv run jenkins-jobs --conf $(call get-config) -l $(JJB_LOG_LEVEL) delete \$$job ; \
      done"

clean:
	@echo -e "$(COLOR)* Removing useless files$(NO_COLOR)"
	@rm -f $(LOCAL_PATH)/xml/*
	@rm -f $(LOCAL_PATH)/etc/secure.*ini

envsetup: $(LOCAL_PATH)/Pipfile.lock

$(LOCAL_PATH)/Pipfile.lock: $(LOCAL_PATH)/Pipfile \
                            $(LOCAL_PATH)/Makefile \
			    | .venv/bin/pipenv
	@echo -e "$(COLOR)* Installing pre-requisites$(NO_COLOR)"
	$| install

$(secure-ini-path): ~/.netrc
	@echo -e "$(COLOR)* Generating secure.ini file from .netrc$(NO_COLOR)"
	@bash -c "\
      host=\$$(echo $(JENKINS_URL) | sed -r -e 's|^http(s)?://||' -e 's|/$$||') && \
      username=\$$(grep \$$host ~/.netrc | awk '{ print \$$4; }') && \
      password=\$$(grep \$$host ~/.netrc | awk '{ print \$$6; }') && \
      m4 -DUSERNAME=\$$username -DPASSWORD=\$$password -DURL=$(JENKINS_URL) \
      $(LOCAL_PATH)/etc/secure.ini.m4 > $@"
	@chmod 0600 $@

deployment-env: envsetup $(secure-ini-path)
