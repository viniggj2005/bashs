#!/bin/bash

# Ler o nome do projeto
read -p "Digite o nome do Repositório: " repository

# Verificar se a porta já está em uso
port=$(docker port "$repository" 2>/dev/null | cut -d ':' -f 2)
if [ -n "$port" ]; then
    echo "A porta encontrada é: $port"
else
    while true; do #requisitar uma porta ao usuário até ele fornecer uma porta que não está em uso
        read -p "Digite a porta do projeto: " port
        verifyport=$(docker ps --format '{{.Ports}}' | grep -w "$port")
        if [ -n "$verifyport" ]; then
            echo "A porta: $port já está em uso"
        else
            break
        fi
    done
fi

# Verificar se o projeto necessita de volume
while true; do #requsitar uma resposta até o usuário fornecer uma resposta esperada.
    read -p "O projeto necessita de um volume? [y/n] " volume
    if [ "$volume" = "y" ] || [ "$volume" = "n" ]; then
        break
    else
        echo "Entrada inválida. Por favor, digite 'y' para sim ou 'n' para não."
    fi
done

# Se o volume for necessário, verificar se o diretório existe ou criar o mesmo.
if [ "$volume" = "y" ]; then
    if [ -d "/mnt/$repository" ]; then
        echo "Volume já existe"
    else
        mkdir /mnt/$repository
        echo "O volume foi criado"
    fi
    read -p "Qual diretório do projeto deverá ser referenciado no volume? " workdir
else
    echo "Sem Volume"
fi

# Verificar se o diretório do projeto existe e realizar o git pull ou clone
if [ -d "/documentos/github/$repository" ]; then
    cd /documentos/github/$repository/
    git checkout main
    git pull
else #Caso não exista clonar o repositório diretamente do github.
    cd /documentos/github
    git clone -b main git@github.com:<Dono do Repositório>/$repository.git
    cd /documentos/github/$repository/
fi
# Verificar e copiar o arquivo .env, se existente
if [ -f "/documentos/envs/$repository.txt" ]; then
    cp -i /documentos/envs/$repository.txt /documentos/github/$repository/.env
    echo ".env encontrado"
else #caso contrário encerra o processo mandando o usuário criar a env
    echo ".env não encontrado na pasta envs, crie o mesmo"
    exit 1
fi
# Obter a versão do package.json e a porta exposta do Dockerfile
version=$(cat package.json 2>/dev/null \
    | grep version \
    | head -1 \
    | awk -F: '{ print $2 }' \
    | sed 's/[",]//g')

expose=$(grep -i '^EXPOSE' Dockerfile | awk '{print $2}' 2>/dev/null)

#Verificar se a porta foi encontrada no Dockerfile
if [ -z "$expose" ]; then #caso não tenha porta exposta no Dockerfile ele encerra o processo e manda o usuário ajustar o Dockerfile
    echo "Não tem uma porta exposta, ajuste o Dockerfile"
    exit 1
else #caso tenha porta exposta no Dockerfile ele printa ela para usuário ver.
    echo "Sua porta exposta é: $expose"
fi

# Se não houver versão no package.json, ele solicitará ela ao usuário.
if [ -z "$version" ]; then
    while true; do
        read -p "Insira a versão da imagem que será montada: " version
        if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            echo "O valor '$version' está no formato correto."
            break
        else
            echo "Formato inválido. Por favor, insira no formato 0.0 ou 0.0.0"
        fi
    done
else
    echo "Versão: $version"
    version=${version//[[:blank:]]/}
fi



# Build da repositorym Docker
docker build -t $repository:$version .
docker tag $repository:$version $repository:latest #Renomeia a imagem que montou para latest

# Parar e remover o container existente
docker stop $repository 2>/dev/null #O 2>/dev/null serve para que caso não haja container ele não retorne o erro de container não econtrado para o usuário 
docker rm $repository 2>/dev/null #O 2>/dev/null serve para que caso não haja container ele não retorne o erro de container não econtrado para o usuário 

# Executar o container com ou sem volume
if [ "$volume" = "y" ]; then #Caso tenha sido requisitado um volume será usado este comando para subir o container com o seu volume.
    docker run -it -d -v /mnt/$repository:$workdir -p $port:$expose --name $repository $repository
else #Caso contrario ele subirá o container com este comando.
    docker run -it -d -p $port:$expose --name $repository $repository
fi
