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


PROJECT = $(shell basename $(CURDIR))
SERVER_NAME ?= $(PROJECT)
PORT ?= 8080			# using djangos default port
path ?= ''		    # use an url path in project url.py
UWSGI_PATH?=/etc/uwsgi/sites
APPS = $(sort $(dir $(wildcard */)))
CFG_MK = $(sort $(wildcard ./*/config.mk))
CFG_MK_RUN = $(CFG_MK:%=%.run)
CFG_MK_BUILD = $(CFG_MK:%=%.build)

################################################################################
# INITIALIZE
################################################################################

# initialize the environment
init:
	git clone https://github.com/bennof/django.mk ./.django.mk
	pipenv --three
	pipenv install django
	pipenv run django-admin startproject $(shell basename $(CURDIR)) .

# run a python environment shell (not used)
shell:
	pipenv shell

################################################################################
# BUILD 
################################################################################

build: $(CFG_MK_BUILD)
	pipenv run python manage.py makemigrations
	pipenv run python manage.py migrate
	@echo nothing to do

################################################################################
# RUN - REPL 
################################################################################
run: $(CFG_MK_RUN)
	pipenv run python manage.py makemigrations
	pipenv run python manage.py migrate
	pipenv run python manage.py runserver $(PORT)

.PHONEY: CFG_MK_RUN
%/config.mk.run: %/config.mk
	make -f $< run &
	
.PHONEY: CFG_MK_BUILD
%/config.mk.build: %/config.mk
	make -f $< build 


################################################################################
# INSTALL 
################################################################################

install: install-nginx # defines default install method

install-nginx: $(UWSGI_PATH)/$(PROJECT).ini /etc/systemd/system/$(PROJECT).service /etc/nginx/sites-enabled/$(PROJECT)
	@echo "Install using nginx and uwsgi"

/etc/systemd/system/$(PROJECT).service: $(UWSGI_PATH)/$(PROJECT).ini
	@echo "Create Systemd Service: $@"
	@echo "[Unit]" >> $@
	@echo "Description=$(Project) Django webserver." >> $@
	@echo "After=network.target" >> $@
	@echo "StartLimitIntervalSec=0" >> $@
	@echo "" >> $@
	@echo "[Service]" >> $@
	@echo "Type=simple" >> $@
	@echo "Restart=always" >> $@
	@echo "RestartSec=1" >> $@
	@echo "User=$(USER)" >> $@
	@echo "ExecStart=$(shell which uwsgi) --master --emperor $(UWSGI_PATH) --die-on-term --uid $(USER) --gid www-data --logto /var/log/uwsgi.log" >> $@
	@echo "" >> $@
	@echo "[Install]" >> $@
	@echo "WantedBy=multi-user.target" >> $@
	systemctl start $(PROJECT) && systemctl enable $(PROJECT)

/etc/nginx/sites-available/$(PROJECT): /etc/systemd/system/$(PROJECT).service
	@echo "Create nginx server: $@"
	@echo "server {" > $@
	@echo "    listen 80;" >> $@
	@echo "    server_name $(SERVER_NAME);" >> $@
	@echo "" >> $@
	@echo "    location = /favicon.ico { access_log off; log_not_found off; }" >> $@
	@echo "    location /static/ {" >> $@
	@echo "        root $(CURDIR)/$(PROJECT);" >> $@
	@echo "    }" >> $@
	@echo "" >> $@
	@echo "    location / {" >> $@
	@echo "        include         uwsgi_params;" >> $@
	@echo "        uwsgi_pass      unix:$(CURDIR)/$(PROJECT)/$(PROJECT).sock;" >> $@
	@echo "    }" >> $@
	@echo "}" >> $@

/etc/nginx/sites-enabled/$(PROJECT): /etc/nginx/sites-available/$(PROJECT)
	@echo "Enable nginx server: $@"
	ln -s /etc/nginx/sites-available/$(PROJECT) /etc/nginx/sites-enabled
	service nginx configtest && sudo service nginx restart
	

$(UWSGI_PATH)/$(PROJECT).ini:
	@echo "uWSGI Configuration: $@"
	@echo "[uwsgi]" > $@
	@echo "project = $(PROJECT)" >> $@
	@echo "base = $(CURDIR)" >> $@
	@echo "chdir = %(base)/%(project)" >> $@
	@echo "home = $(shell pipenv --venv)" >> $@
	@echo "module = %(project).wsgi:application" >> $@
	@echo "master = true" >> $@
	@echo "processes = $(shell lscpu | grep -e '^CPU(s):' | cut -f 2 -d ':')" >> $@
	@echo "socket = %(base)/%(project)/%(project).sock" >> $@
	@echo "chmod-socket = 664" >> $@
	@echo "vacuum = true" >> $@



################################################################################
# NEW APPLICATION 
################################################################################
new: 
	@test -n $(n) || echo "ERROR: no app name" && test -n $(n) 
	pipenv run python manage.py startapp $(n)
	echo "/^INSTALLED_APPS\na\n\t'$(n)',\n.\nwq\n" | ed $(shell basename $(CURDIR))/settings.py &> /dev/null
	test -z $(t) || make -f .django.mk/tmpl/$(t).mk new n=$(n) path=$(path)



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
	
