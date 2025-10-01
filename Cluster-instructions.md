Login to Azure

Az login

Get arc credentials

az aks get-credentials --resource-group datawarehouse-rg --name aks-datawarehouse 

Get pods

Kubectl get pod -n airflows 

Apply config file

Kubectl apply -f deployment-airflow.yaml -n airflows

Delete pod 

Kubectl delete deploy airflow-apiserver -n airflows


Redeploy pod

Kubectl apply -f deployment-airflow.yaml -n airflows

Port forward pod

Kubectl port-forward airflow-apiserver-c5ff94d5b-rbvm6 -n airflows 5555:8080

Exec into pod

kubectl exec -ti <pod name>  -n airflows -- /bin/bash

Get pass

cat /opt/airflow/simple_auth_manager_passwords.json.generated
