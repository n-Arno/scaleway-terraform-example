all: .terraform build

.terraform:
	terraform init

build:
	terraform plan --out=.current.plan 1>/dev/null 2>&1 || terraform plan
	terraform apply --auto-approve .current.plan
	rm -f .current.plan

clean:
	- terraform plan --destroy --out=.current.plan 1>/dev/null 2>&1 && terraform apply --destroy --auto-approve .current.plan && rm -f .current.plan

dist-clean: clean
	rm -rf .terraform terraform.tfstate terraform.tfstate.backup
