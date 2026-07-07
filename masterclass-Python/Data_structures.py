List_of_cloud=["AWS", "Azure", "oracle", "GCP"]
list_of_env= ["dev", "test", "prod"]




for i in list_of_env:
    if i=="prod":
        print("Selected Cloud is Azure")

#Dictionary

dict_of_cloud={
    "aws": "Amazon web services",
    "azure":"Microsoft Azure",
    "gcp": "Google"
}

print(dict_of_cloud["aws"])
print(dict_of_cloud.get("azure1","not found"))

dict_of_cloud.update({"name": "bunty"})
print(dict_of_cloud)






