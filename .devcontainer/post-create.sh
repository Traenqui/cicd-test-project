#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Update package lists
echo "Updating package lists..."
sudo apt update

# Install required build tools and libraries for Python
echo "Installing dependencies..."
sudo apt install -y \
  make build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
  libncurses5-dev libncursesw5-dev xz-utils tk-dev \
  libffi-dev liblzma-dev git

# Install pyenv
echo "Installing pyenv..."
curl -fsSL https://pyenv.run | bash

echo "Configuring shell environment for pyenv..."
{
  echo 'export PYENV_ROOT="$HOME/.pyenv"'
  echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
  echo 'eval "$(pyenv init --path)"'
  echo 'eval "$(pyenv init -)"'
  echo 'eval "$(pyenv virtualenv-init -)"'
} >> ~/.bashrc

# Load pyenv into current shell session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "Installing Python 3.12.10 via pyenv..."
pyenv install 3.13.7
pyenv local 3.13.7

echo "Updating pip..."
pip install --upgrade pip

echo "Install dependencies..."
if [[ -s "requirements.txt" ]]; then
  pip install -r requirements.txt
fi

if [[ -s "requirements-dev.txt" ]]; then
  pip install -r requirements-dev.txt
fi

brew install act

echo "Setup complete!"