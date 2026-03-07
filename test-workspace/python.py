"""
Solve the quadratic equation ax**2 + bx + c = 0
"""
import math

a = 1; b = 3; c = -6
d = (b**2) - (4*a*c)
sol1 = (-b-math.sqrt(d))/(2*a)
sol2 = (-b+math.sqrt(d))/(2*a)

print('The solution are {0} and {1}'.format(sol1,sol2))

# Class example
class Rectangle(object):
    def __init__(self, width=1, height=1):
        self.width = width
        self.height = height

    @property
    def area(self):
        return self.width * self.height

    def __str__(self):
        return 'length = {}, width = {}'.format(self.length, self.width)