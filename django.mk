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

PORT?=8080

path?=''

init:
	pipenv --three
	pipenv install django
	pipenv run django-admin startproject $(shell basename $(CURDIR)) .

shell:
	pipenv shell

run: 
	pipenv run python manage.py makemigrations
	pipenv run python manage.py migrate
	pipenv run python manage.py runserver $(PORT)

build:
	@echo nothing to do

new: 
	@test -n $(n) || echo "ERROR: no app name" && test -n $(n) 
	pipenv run python manage.py startapp $(n)
	echo "/^INSTALLED_APPS\na\n\t'$(n)',\n.\nwq\n" | ed $(shell basename $(CURDIR))/settings.py &> /dev/null
	echo "/^]\ni\n\tpath($(path),include('$(n).urls')),\n.\nwq\n" | ed $(shell basename $(CURDIR))/urls.py &> /dev/null
	echo "/^from django.urls.\nc\nfrom django.urls import path, include\n.\nwq\n" | ed $(shell basename $(CURDIR))/urls.py &> /dev/null
	test -z $(t) || make -f .django.mk/tmpl/$(t).mk new n=$(n) 

tt:
	echo "/^]\ni\n\tpath($(path),include('$(n).urls')),\n.\nwq\n" | ed $(shell basename $(CURDIR))/urls.py 

clean:
	@echo nothing to do

info:
	@python --version
	@pipenv run python -c "import django; print('Django '+django.get_version())"
	@echo "Project $(shell basename $(CURDIR)) ($(CURDIR))"
	
