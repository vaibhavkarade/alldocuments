num1=float(input("Enter the first number"))
num2=float(input("Enter the Second Number"))
choice=input("Enter the operation to be performed + - * /")
if choice=="+":
    sum=num1+num2
    print("The Sum is ", sum)
    print(type(sum))
elif choice=="-":
    diff=num1-num2
    print("The diff is ",diff)
elif choice=="*":
    mul=num1*num2
    print("The Mul is ",mul)
elif choice=="/":
    div=num1/num2
    print("The Div is ", div)
else:
    print("Invalid choice")

