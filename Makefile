# get OS X to have `pip install --user` target in $PATH
PATH := ${HOME}/.local/bin:${PATH}

# virtualenvs(' paths) handled by make rules
VENV_DEV_PATH := .venvs/dev
VENV_RELEASE_PATH := .venvs/release

# evaluate lazily: package name when installing from PyPIs
PACKAGE_NAME = RESTinstance

# evaluate lazily: checks before build and after installed
SANITY_CHECK = robot --outputdir results README.rst
SMOKE_CHECK = python -c "import REST; print(REST.__version__)"


.DEFAULT_GOAL := all

.PHONY: all
all: test build install atest ## Run test, build, install and atest (default)

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+[0-9]*:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: _venv_dev
_venv_dev:
	virtualenv --version >/dev/null || pip install --user virtualenv
	test -d "${VENV_DEV_PATH}" || virtualenv --no-site-packages "${VENV_DEV_PATH}"
	. "${VENV_DEV_PATH}/bin/activate" && \
	pip install --quiet -r requirements-dev.txt

.PHONY: _venv_release
_venv_release:
	virtualenv --version >/dev/null || pip install --user virtualenv
	virtualenv --clear --no-site-packages "${VENV_RELEASE_PATH}"
	. "${VENV_RELEASE_PATH}/bin/activate" && \
	pip install --upgrade pip setuptools wheel

.PHONY: pur
pur: _venv_dev ## Update requirements-dev for locked versions
	. "${VENV_DEV_PATH}/bin/activate" && \
	pur -r requirements-dev.txt --no-recursive

.PHONY: black
black: ## Reformat source code in-place
	. "${VENV_DEV_PATH}/bin/activate" && black .

.PHONY: check-manifest
check-manifest: ## Run check-manifest for MANIFEST.in completeness
	. "${VENV_DEV_PATH}/bin/activate" && check-manifest .

.PHONY: flake8
flake8: ## Run flake8 for static code analysis
	. "${VENV_DEV_PATH}/bin/activate" && flake8

.PHONY: mypy
mypy: ## Run mypy for static type checking
	. "${VENV_DEV_PATH}/bin/activate" && mypy .

.PHONY: pyroma
pyroma: ## Run pyroma for Python packaging best practices
	. "${VENV_DEV_PATH}/bin/activate" && pyroma .

.PHONY: dc
dc: ## Start docker-composed test API on background
	# If you have no docker(-compose), run acceptance tests with:
	#
	# npm install -g mountebank
	# mb --localOnly  --allowInjection --configfile testapi/apis.ejs
	# robot --outputdir results tests/
	docker-compose up -d

.PHONY: dc_rm
dc_rm: ## Stop and remove docker-composed test API
	docker-compose down --volumes

.PHONY: libdoc
libdoc: install ## Regenerate library keyword documentation
	python -m robot.libdoc REST docs/index.html

.PHONY: atest
atest: dc ## Run acceptance tests
	RUN_ARGS="--network=host --env HTTP_PROXY --env HTTPS_PROXY" ./rfdocker --xunit xunit.xml tests/

.PHONY: atest_py2
atest_py2: dc ## Run acceptance tests on Python 2
	RUN_ARGS="--network=host --env HTTP_PROXY --env HTTPS_PROXY" BUILD_ARGS="-f Dockerfile.python2" BUILD_NAME="restinstance-python2" ./rfdocker tests/

.PHONY: test
test: _venv_dev ## Run tests, installs requirements(-dev) first
	. "${VENV_DEV_PATH}/bin/activate" && pytest

.PHONY: retest
retest: ## Run failed tests only, if none, run all
	. "${VENV_DEV_PATH}/bin/activate" && \
	pytest --last-failed --last-failed-no-failures all

.PHONY: build
build: _venv_release ## Build source dist and wheel
	. "${VENV_RELEASE_PATH}/bin/activate" && pip install .
	##########################################
	### Sanity check by README.rst before building dists ###
	. "${VENV_RELEASE_PATH}/bin/activate" && ${SANITY_CHECK} && \
	python setup.py clean --all bdist_wheel sdist && \
	pip install --upgrade twine

.PHONY: install
install: ## Install package from source tree, as --editable
	pip install --editable .
	###############################################
	### Smoke check after installed from source ###
	${SMOKE_CHECK}

.PHONY: install_test
install_test: ## Install the latest test.pypi.org release
	pip install --force-reinstall \
		--index-url https://test.pypi.org/simple/ \
		--extra-index-url https://pypi.org/simple ${PACKAGE_NAME}

.PHONY: install_pypi
install_pypi: ## Install the latest PyPI release
	pip install --force-reinstall --upgrade ${PACKAGE_NAME}

.PHONY: uninstall
uninstall: ## Uninstall the package, regardless of its origin
	pip uninstall --yes ${PACKAGE_NAME}

.PHONY: publish_test
publish_test: ## Publish dists to test.pypi.org
	. "${VENV_RELEASE_PATH}/bin/activate" && \
	twine upload --repository-url https://test.pypi.org/legacy/ dist/*

.PHONY: publish_pypi
publish_pypi: ## Publish dists to PyPI
	. "${VENV_RELEASE_PATH}/bin/activate" && twine upload dist/*

.PHONY: clean
clean: ## Remove .venvs, builds, dists, and caches
	rm -rf dist build */*.egg-info */__pycache__ */**/__pycache__
	rm -rf pip-wheel-metadata
	rm -rf .venvs
	rm -rf .pytest_cache .mypy_cache
	rm -rf results
	rm -f log.html output.xml report.html *.demo.json
	rm -f mb.log mb1.log mb.pid
	rm -f .coverage
