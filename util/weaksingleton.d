
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


///Singleton with no global access.
module util.weaksingleton;


/**
 * Singleton template mixin with support for polymorphism, without global access.
 *
 * Note: Any non-abstract weak singleton class must call singletonCtor() in its ctor
 *       and singletonDtor in its dtor or die() method.
 */
template WeakSingleton()
{
    protected:
        ///Singleton object itself.
        static typeof(this) _instance_ = null;

    public:
        ///Enforce only single instance at any given time.
        void singletonCtor()
        {
            assert(_instance_ is null, 
                  "Trying to construct a weak singleton that is already constructed: "
                  ~ typeid(typeof(this)).toString);
            _instance_ = this;
        }

        ///Enforce only single instance at any given time.
        void singletonDtor()
        {
            assert(_instance_ !is null, 
                  "Trying to destroy a weak singleton that is not constructed: "
                  ~ typeid(typeof(this)).toString);
            _instance_ = null;
        }
}

