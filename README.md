#### What it does:

Clientsided Uppers aims at fixing the delay of deploying a FirstAidKit (FAK) as a client with high ping towards the host.
During the time it takes to get an answer of the host to actually place down the FAK, Uppers does not apply, so it is possible to effectively go down on an Uppers-enabled FAK without being on cooldown.
With this mod FAKs which were already deployed clientsided, but havent been placed from the hostside, are made viable to trigger uppers for the deployee.

#### How the code works:

As soon as you deploy a FAK before the request to place one gets sent to the host, the information gets saved in a list of clientsided FAKs. When you go down and it doesnt find a fitting FAK in the regular list, it starts searching in the clientsided list and if it finds a fitting FAK it triggers the Uppers effect without actually using a FAK yet.
Then it adds this clientsided-used FAK into another list.
This list is used when the FAK sync is received at a client, now the list is checked if it contains the FAK that the host has just added.
This then means it has already been used and effectively shouldn't exist, so it instantly get a request to be synced as used.

I know that a person with a better ping than the one using this mod will be able to trigger and use the FAK before it is received at the deploying client and the deploying client may have used it clientsided already, so it was essentially used twice. But I don't know if this isn't possible already and not a problem.
