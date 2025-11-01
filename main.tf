# In your local repo
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
git add .terraform.lock.hcl
git commit -m "Fix provider schema mismatch for Terraform Cloud"
git push
