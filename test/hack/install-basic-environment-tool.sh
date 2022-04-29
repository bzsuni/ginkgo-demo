#!/usr/bin/env bash
set -eo pipefail
#set -u
set -x

function msg() {
   if [[ $# -ne 1 ]]; then echo "[func msg] one arg needed"; exit 1; fi
    echo -e "\033[35m $1 \033[0m"
}
function err() {
   if [[ $# -ne 1 ]]; then echo "[func err] one arg needed"; exit 1; fi
   echo -e "\033[31m $1 \033[0m"
}
function succ() {
   if [[ $# -ne 1 ]]; then echo "[func succ] one arg needed"; exit 1; fi
   echo -e "\033[32m $1 \033[0m"
}

OS=$(uname | tr 'A-Z' 'a-z')

# update yum
#yum -y update

# install go
if ! $(go version > /dev/null 2>&1); then
  msg "install go1.18..."
  sudo wget "https://golang.google.cn/dl/go1.18.linux-amd64.tar.gz"
  sudo tar -C /usr/local -xzf go1.18.linux-amd64.tar.gz
  sudo rm -rf go1.18.linux-amd64.tar.gz

  # add go path
  if ! $(cat $HOME/.bashrc | grep GOROOT > /dev/null 2>&1); then
    sudo echo -e "export GOROOT=/usr/local/go" >> $HOME/.bashrc
  fi
  if ! $(cat $HOME/.bashrc | grep GOPATH > /dev/null 2>&1); then
    sudo echo -e "export GOPATH=$HOME/go" >> $HOME/.bashrc
  fi
  if ! $(cat $HOME/.bashrc | grep GOBIN > /dev/null 2>&1); then
    sudo echo -e "export GOBIN=$HOME/go/bin" >> $HOME/.bashrc
  fi
  if ! $(cat $HOME/.bashrc | grep -w PATH | grep GOPATH > /dev/null 2>&1); then
     sudo echo -e 'export PATH=$PATH:$GOPATH:$GOBIN:$GOROOT/bin' >> $HOME/.bashrc
     sudo ln -s /usr/local/go/bin/go /usr/local/bin/go
  fi
  if ! $(go version > /dev/null 2>&1); then
    err "failed install go";
    exit 1;
  else
    succ "go has been installed succeed"
  fi
  # set go env
  go env -w GOPROXY=https://goproxy.cn,direct
  go env -w GO111MODULE=on
else
  msg "go has already been installed"
fi

# install git
if $(git version > /dev/null 2>&1) && [[ $(git version | cut -d " " -f 3) == "2.30.1" ]]; then
  msg "git 2.30.1 has already been installed"
else
  msg "install git2.30.1 ..."
  sudo yum -y install curl-devel expat-devel gettext-devel openssl-devel zlib-devel gcc perl-ExtUtils-MakeMaker
  pushd /tmp
  sudo wget --no-check-certificate https://www.kernel.org/pub/software/scm/git/git-2.30.1.tar.gz
  sudo tar xf git-2.30.1.tar.gz
  pushd git-2.30.1
  sudo make prefix=git all
  sudo make prefix=/usr/local/git install
  popd
  popd
  sudo echo -e 'export PATH=$PATH:/usr/local/git/bin' >> $HOME/.bashrc
  sudo yum -y remove git
  source $HOME/.bashrc
  sudo ln -s /usr/local/git/bin/git /usr/local/bin/git
  if [[ $(git version | cut -d " " -f 3) != "2.30.1" ]]; then
    err "failed install git 2.30.1"
    exit 1
  else
    succ "git 2.30.1 has been installed succeed"
  fi
fi

# install kubectl
if ! $(kubectl -h > /dev/null 2>&1); then
  msg "install kubectl..."
  curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/$OS/amd64/kubectl
  chmod +x /usr/local/bin/kubectl
  sudo echo -e 'export PATH=$PATH:/usr/local/bin' >> $HOME/.bashrc
  source $HOME/.bashrc
  if ! $(kubectl -h > /dev/null 2>&1); then
    err "failed install kubectl"
    exit 1
  else
    succ "kubectl has been installed succeed"
  fi
else
  msg "kubectl has already been installed"
fi

# install kind
if ! $(kind > /dev/null 2>&1); then
  msg "install kind..."
  curl -Lo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/v0.12.0/kind-$OS-amd64
  chmod +x /usr/local/bin/kind
  if ! $(kind > /dev/null 2>&1); then
    err "failed install kind"
    exit 1
  else
    succ "kind has been installed succeed"
  fi
else
  msg "kind has already been installed"
fi

# install helm
if ! $(helm > /dev/null 2>&1); then
  msg "install helm..."
  pushd /tmp
  curl -Lo helm.tar.gz "https://get.helm.sh/helm-v3.8.1-$OS-amd64.tar.gz"
  tar -xzvf helm.tar.gz
  mv $OS-amd64/helm helm
  mv helm /usr/local/bin
  chmod +x /usr/local/bin/helm
  popd
  if ! $(helm > /dev/null 2>&1); then
    err "failed install helm"
  else
    succ "helm has been installed succeed"
  fi
else
  msg "helm has already been installed"
fi

# install p2ctl
if ! $(p2ctl --version > /dev/null 2>&1); then
  msg "install p2ctl..."
  curl -Lo /usr/local/bin/p2ctl https://github.com/wrouesnel/p2cli/releases/download/r13/p2-$OS-x86_64
  chmod +x /usr/local/bin/p2ctl
  if ! $(p2ctl --version > /dev/null 2>&1); then
    err "failed install p2ctl"
  else
    succ "p2ctl has been installed succeed"
  fi
else
  msg "p2ctl has already been installed"
fi

# install nmap jq
needs="nmap jq"
for need in $needs; do
  if ! $($need --version > /dev/null 2>&1); then
    msg "install $need ..."
    sudo yum -y install $need
    if ! $($need --version > /dev/null 2>&1); then
      err "failed install $need"; exit 1;
    else
      succ "install $need succeed"
    fi
  else
    msg "$need has already been installed"
  fi
done

# install docker
if ! $(which docker > /dev/null 2>&1); then
  msg "install docker..."
  sudo yum -y install docker
  sudo systemctl start docker
  if ! $(which docker > /dev/null 2>&1); then
    err "failed install docker";
    exit 1;
  else
    succ "docker has been installed succeed"
  fi
  sudo systemctl enable docker

  sudo groupadd docker
  sudo gpasswd -a $USER docker
  sudo newgrp docker
else
  msg "docker has already been installed"
fi
# resolve runner run docker permission denied
#sudo chmod a+rwx /var/run/docker.sock
