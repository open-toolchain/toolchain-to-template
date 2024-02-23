import unittest
import os
from mock import patch


if __name__ == "__main__" and __package__ is None:
    from sys import path
    from os.path import dirname as dir
    path.append(dir(path[0]))
    
import update_secure_value


class Test(unittest.TestCase):
    def setUp(self):
        super().setUp()
        

    def tearDown(self):
        return super().tearDown()
    

    def test_isHardCoded(self):
        self.assertEqual(update_secure_value.isHardCoded("crn:v1:bluemix:public:secrets-manager:eu-gb:a/1fdd4e89af9d4f51b471e3ea625f6234:f0f10710-dcbe-454d-b2e1-c7b918f73016:secret:ea15de0e-31a0-3bcb-775d-0f9441eac9ae"), False)
        self.assertEqual(update_secure_value.isHardCoded(""), False)
        self.assertEqual(update_secure_value.isHardCoded("{vault::key-protect.secrets-probe-secret-1}"), False)
        self.assertEqual(update_secure_value.isHardCoded("hard_coded"), True)
    

if __name__ == '__main__':
    unittest.main()