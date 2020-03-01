# Copyright 2020 Benjamin 'Benno' Falkner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to 
# deal in the Software without restriction, including without limitation the 
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
# sell copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

# GLOBAL VARIABLES
PROJECT = $(shell basename $(CURDIR))
SERVER_NAME ?= $(PROJECT)
ALLOWED_HOSTS ?= $(SERVER_NAME:%='%',)
PORT ?= 8080			# using djangos default port
HOST ?= 127.0.0.1		# using djangos default port
INSTALL_PATH ?= /var/www

#USER = www-data
GROUP = www-data

UWSGI_PATH?=/etc/uwsgi/sites
APPS = $(sort $(dir $(wildcard */)))

DEP_MK = $(sort $(wildcard ./*/Makefile))
DEP_MK_RUN = $(CFG_MK:%=%.run)
DEP_MK_BUILD = $(CFG_MK:%=%.build)

#Deprecated
CFG_MK = $(sort $(wildcard ./*/config.mk))
CFG_MK_RUN = $(CFG_MK:%=%.run)
CFG_MK_BUILD = $(CFG_MK:%=%.build)

# special variables for targets
path ?= ''		    # use an url path in project url.py



################################################################################
# INITIALIZE
################################################################################

# initialize the environment
init: $(PROJECT) 

$(PROJECT): .django.mk .venv
	pipenv run django-admin startproject $(shell basename $(CURDIR)) .

.venv:
	PIPENV_VENV_IN_PROJECT=true pipenv --three
	pipenv install django

.django.mk:
	git clone https://github.com/bennof/django.mk ./.django.mk



################################################################################
# BUILD 
################################################################################

build: .django.mk pip_install $(DEP_MK_BUILD)
	pipenv run python manage.py makemigrations
	pipenv run python manage.py migrate

.PHONEY: $(DEP_MK_BUILD)
%/Makefile.build: %/Makefile
	make -f $< build 

pip_install:
	pipenv sync || pipenv install

################################################################################
# INSTALL 
################################################################################

install: prepare-django 

prepare-django: prepare-db $(INSTALL_PATH)/$(PROJECT)
	grep -qxF 'STATIC_ROOT = os.path.join(BASE_DIR, "static/")' $(INSTALL_PATH)/$(PROJECT)/$(PROJECT)/settings.py || echo 'STATIC_ROOT = os.path.join(BASE_DIR, "static/")' >> $(INSTALL_PATH)/$(PROJECT)/$(PROJECT)/settings.py
	cd $(INSTALL_PATH)/$(PROJECT); pipenv run python manage.py collectstatic
	chown -R $(USER):$(GROUP) $(INSTALL_PATH)/$(PROJECT)

prepare-db: 

$(INSTALL_PATH)/$(PROJECT):
	mkdir -p $(INSTALL_PATH)/$(PROJECT)
	cp -rf . $(INSTALL_PATH)/$(PROJECT)/



install-uwsgi: install $(UWSGI_PATH)/$(PROJECT).ini 

$(UWSGI_PATH)/$(PROJECT).ini: prepare-django
	@echo "Install uwsgi site $(PROJECT)"
	@echo "uWSGI Configuration: $@"
	@echo "[uwsgi]" > $@
	@echo "project = $(PROJECT)" >> $@
	@echo "base = $(INSTALL_PATH)/$(PROJECT)" >> $@
	@echo "chdir = %(base)" >> $@
	@echo "home = $(shell pipenv --venv)" >> $@
	@echo "module = %(project).wsgi" >> $@
	@echo "master = true" >> $@
	@echo "processes = $(shell lscpu | grep -e '^CPU(s):' | cut -f 2 -d ':')" >> $@
	@echo "socket = %(base)/%(project)/%(project).sock" >> $@
	@echo "chmod-socket = 664" >> $@
	@echo "vacuum = true" >> $@
	
install-uwsgi-service: /etc/systemd/system/$(PROJECT).service 

/etc/systemd/system/$(PROJECT).service: $(UWSGI_PATH)/$(PROJECT).ini
	@echo "Install uwsgi service: $(PROJECT)"
	@echo "Create Systemd Service: $@"
	@echo "[Unit]" > $@
	@echo "Description=$(PROJECT) Django webserver." >> $@
	@echo "After=network.target" >> $@
	@echo "StartLimitIntervalSec=0" >> $@
	@echo "" >> $@
	@echo "[Service]" >> $@
	@echo "Type=simple" >> $@
	@echo "Restart=always" >> $@
	@echo "RestartSec=1" >> $@
	@echo "User=$(USER)" >> $@
	@echo "ExecStart=$(shell which uwsgi) --master --emperor $(UWSGI_PATH) --die-on-term --uid $(USER) --gid www-data --logto /var/log/uwsgi/$(PROJECT).log" >> $@
	@echo "" >> $@
	@echo "[Install]" >> $@
	@echo "WantedBy=multi-user.target" >> $@
	mkdir -p /var/log/uwsgi
	chgrp adm /var/log/uwsgi
	systemctl start $(PROJECT) && systemctl enable $(PROJECT)


# install for nginx
install-nginx:  install-uwsgi /etc/nginx/sites-available/$(PROJECT)
install-nginx-enable:  /etc/nginx/sites-enabled/$(PROJECT)

/etc/nginx/sites-available/$(PROJECT): 
	@echo "Install nginx site $(PROJECT)"
	@echo "Create nginx server: $@"
	@echo "server {" > $@
	@echo "    listen 80;" >> $@
	@echo "    server_name $(SERVER_NAME);" >> $@
	@echo "" >> $@
	@echo "    location = /favicon.ico { access_log off; log_not_found off; }" >> $@
	@echo "    location /static/ {" >> $@
	@echo "        root $(INSTALL_PATH)/$(PROJECT);" >> $@
	@echo "    }" >> $@
	@echo "" >> $@
	@echo "    location / {" >> $@
	@echo "        include         uwsgi_params;" >> $@
	@echo "        uwsgi_pass      unix:$(INSTALL_PATH)/$(PROJECT)/$(PROJECT)/$((PROJECT).sock;" >> $@
	@echo "    }" >> $@
	@echo "}" >> $@

/etc/nginx/sites-enabled/$(PROJECT): install-nginx
	@echo "Enable nginx server: $@"
	ln -s /etc/nginx/sites-available/$(PROJECT) /etc/nginx/sites-enabled
	service nginx configtest && sudo service nginx restart
	



################################################################################
# NEW APPLICATION 
################################################################################
new: 
	@test -n $(n) || echo "ERROR: no app name" && test -n $(n) 
	pipenv run python manage.py startapp $(n)
	echo "/^INSTALLED_APPS\na\n\t'$(n)',\n.\nwq\n" | ed $(shell basename $(CURDIR))/settings.py &> /dev/null
	test -z $(t) || make -f .django.mk/tmpl/$(t).mk new n=$(n) path=$(path)

################################################################################
# RUN - REPL 
################################################################################
run: $(CFG_MK_RUN)
	pipenv run python manage.py makemigrations
	pipenv run python manage.py migrate
	pipenv run python manage.py runserver $(HOST):$(PORT)

.PHONEY: CFG_MK_RUN
%/config.mk.run: %/config.mk
	make -f $< run &
	
.PHONEY: CFG_MK_BUILD
%/config.mk.build: %/config.mk
	make -f $< build 

# run a python environment shell (not used)
shell:
	pipenv shell


################################################################################
# CLEAN 
################################################################################

clean:
	@echo nothing to do

################################################################################
# HELP 
################################################################################

help:
	@echo nothing to do

################################################################################
# INFO 
################################################################################
# used for debugging
info:
	@python --version
	@pipenv run python -c "import django; print('Django:  '+django.get_version())"
	@echo "Project    $(shell basename $(CURDIR)) ($(CURDIR))"
	@echo "Directory: $(CURDIR)"
	@echo "APPS:      $(APPS)"
	@echo "Build:     $(CFG_MK)"
	@echo "Server name:     $(SERVER_NAME)"
	@echo "Allowed hosts:   $(ALLOWED_HOSTS)"
	
