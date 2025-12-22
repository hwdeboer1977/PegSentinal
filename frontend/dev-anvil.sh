# chmod +x dev-anvil.sh
# ./dev-anvil.sh

#!/usr/bin/env bash
set -a
source ../v4_hook/.env.anvil
set +a

export NEXT_PUBLIC_RPC_URL=$RPC_URL
export NEXT_PUBLIC_VAULT_ADDRESS=$VAULT_ADDRESS
export NEXT_PUBLIC_POOL_ADDRESS=$POOL_ADDRESS

npm run dev

